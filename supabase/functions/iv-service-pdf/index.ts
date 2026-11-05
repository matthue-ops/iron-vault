// Retired by 038: keep this denying endpoint until its Supabase deployment is deleted.
import {serve} from '../_shared/runtime.ts';
serve(async()=>{throw Error('Invalid request.');});
