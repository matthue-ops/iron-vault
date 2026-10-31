/* UI for administrator-granted report access. The RPC enforces authority again. */
(function (root) {
    'use strict';
    async function render(client, tenantId, containerId, document = root.document) {
        const container = document.getElementById(containerId);
        if (!container) return;
        container.textContent = 'Loading authenticated staff permissions…';
        try {
            const actor = await root.IronVaultAuth.requireRole(client, {
                roles:['super_admin','owner'], tenantId, allowGlobalSuperAdmin:true
            });
            const {data:staff, error} = await client.rpc('iv_list_staff_financial_report_access', {p_tenant:tenantId});
            if (error || !Array.isArray(staff)) throw new Error('Report permission controls are unavailable. Verify the security migrations first.');
            container.textContent = '';
            if (!staff.length) {container.textContent = 'No authenticated staff accounts are linked to this gym.';return;}
            for (const account of staff) {
                const row = document.createElement('div');
                row.className = 'flex items-center justify-between gap-2 py-2 text-xs';
                const label = document.createElement('span');
                label.textContent = (account.email || 'Staff account')+' — '+account.user_id;
                const button = document.createElement('button');
                button.type = 'button';
                button.className = 'px-3 py-2 rounded bg-slate-800 text-white';
                button.textContent = account.financial_reports_read ? 'Revoke reports' : 'Allow reports';
                button.disabled = account.user_id === actor.user_id;
                button.onclick = async () => {
                    button.disabled = true;
                    try {
                        await root.IronVaultAuth.requireRole(client, {
                            roles:['super_admin','owner'],tenantId,allowGlobalSuperAdmin:true
                        });
                        const {error:writeError} = await client.rpc('iv_set_staff_financial_report_access', {
                            p_tenant:tenantId,p_user:account.user_id,p_enabled:!account.financial_reports_read
                        });
                        if (writeError) throw new Error('Permission was not confirmed. Reload and verify your administrator access.');
                        await render(client,tenantId,containerId,document);
                    } catch (writeError) {
                        button.disabled = false;
                        const message = document.createElement('p');
                        message.textContent = writeError.message;
                        row.appendChild(message);
                    }
                };
                row.appendChild(label);row.appendChild(button);container.appendChild(row);
            }
        } catch (error) {container.textContent = error.message;}
    }
    root.IronVaultStaffReports = Object.freeze({render});
    if (typeof module === 'object' && module.exports) module.exports = root.IronVaultStaffReports;
})(globalThis);
