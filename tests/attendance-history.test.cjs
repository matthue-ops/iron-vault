const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const R=require('../assets/reports-analysis.js');
function entry(day,expiry,days,plan='1-Week Pass'){return {created_at:day+'T06:00:00+08:00',membership_snapshot:{version:1,business_day:day,expiration_date:expiry,days_remaining:days,plan,status:'ACTIVE'}};}
test('weekly history counts six days after the first day, then five and zero on the last day',()=>{
 for(const [day,days] of [['2026-11-04',6],['2026-11-05',5],['2026-11-10',0]])assert.match(R.attendanceDetails(entry(day,'2026-11-10',days)).expiry,new RegExp('10 Nov 2026.*'+days+' days left'));
});
test('30-day monthly history handles month boundaries without subtracting skipped visits',()=>{
 assert.match(R.attendanceDetails(entry('2026-11-04','2026-12-03',29,'1-Month Unlimited')).expiry,/3 Dec 2026.*29 days left/);
 assert.match(R.attendanceDetails(entry('2026-11-09','2026-12-03',24,'1-Month Unlimited')).expiry,/24 days left/);
 assert.match(R.attendanceDetails(entry('2028-02-01','2028-03-01',29,'1-Month Unlimited')).expiry,/29 days left/);
});
test('day pass shows its actual Manila date, not a countdown or current date',()=>{
 const row=entry('2026-11-04','2026-11-04',0,'1-Day Pass');row.created_at='2026-11-03T16:05:00Z';
 assert.equal(R.attendanceDetails(row).expiry,'Valid on 4 Nov 2026');
});
test('renewals, current dates and missing/deleted profiles cannot rewrite saved attendance',()=>{
 const row=entry('2026-11-04','2026-11-10',6),before=R.attendanceDetails(row);
 R.analyze({attendance:[row],members:[{id:'a',plan:'1-Month Unlimited',expiration_date:'2027-01-01',status:'INACTIVE'}]},'2026-11-01','2026-11-30','2026-12-01');
 assert.deepEqual(R.attendanceDetails(row),before);assert.equal(before.status,'ACTIVE');
 assert.equal(R.attendanceDetails({created_at:row.created_at}).plan,'History unavailable');
 row.membership_snapshot.days_remaining=999;assert.equal(R.attendanceDetails(row).expiry,'History unavailable');
});
test('migration corrects new plan terms and atomically captures history without rewriting existing records',()=>{
 const sql=fs.readFileSync('supabase/migrations/202611040029_attendance_membership_history.sql','utf8');
 assert.equal(sql,fs.readFileSync('supabase/manual/attendance_membership_history.sql','utf8'));
 for(const text of ["key:='day';days:=0","key:='week';days:=6","key:='month';days:=29",'BEFORE INSERT ON public.iv_attendance_logs','id=NEW.member_id AND tenant_id=NEW.tenant_id FOR SHARE',"AT TIME ZONE 'Asia/Manila'",'NEW.membership_snapshot:=jsonb_build_object',"'days_remaining',greatest(0,expiry-business_day)","SET search_path=''"])assert.ok(sql.includes(text),text);
 assert.equal(/UPDATE public.members|UPDATE public.iv_attendance_logs|DELETE FROM|TRUNCATE/i.test(sql),false);
});
