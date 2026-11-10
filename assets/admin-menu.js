/* Move existing menu controls only: retain handlers, visibility and permission rules. */
(function(root){
 'use strict';
 const d=root.document,menu=d.querySelector?.('#admin-account-menu .admin-menu-panel');if(!menu)return;
 for(const id of ['btn-reports-analytics','btn-gym-portal-qr','owner-subscription-menu','btn-announcements','btn-staff-management','btn-membership-pricing','btn-refunds','btn-my-account','btn-gym-legal','btn-admin-logout','btn-gym-appearance']){
  const control=d.getElementById(id);if(control?.parentElement===menu)menu.append(control);
 }
})(globalThis);
