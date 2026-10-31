/* Shared Auth-backed entry gate for both existing master dashboards. */
(function (root) {
    'use strict';
    function install(app, client, options = {}) {
        const document = options.document || root.document;
        const session = options.sessionStorage || root.sessionStorage;
        const cache = options.localStorage || root.localStorage;
        const notify = options.notify || root.alert;
        const hub = options.hub === true;
        const originalLoad = app.loadData;
        const node = id => document.getElementById(id);
        const hide = id => node(id)?.classList.add('hidden');
        const show = id => node(id)?.classList.remove('hidden');
        let generation = 0;
        let activeUserId = null;
        const authorize = () => root.IronVaultAuth.requireRole(client, {roles: ['super_admin']});
        function clear() {
            generation++;
            activeUserId = null;
            root.IronVaultAuth.clearState(session, cache);
            app.owners = [];
            app.members = [];
            app.currentInspectOwnerId = null;
            app.visiblePasswords = {};
            if (node('owners-tbody')) node('owners-tbody').textContent = '';
            if (node('inspect-members-tbody')) node('inspect-members-tbody').textContent = '';
            if (node('inspect-staff-list')) node('inspect-staff-list').textContent = '';
            for (const id of ['stat-gyms', 'stat-members', 'owner-count']) {
                if (node(id)) node(id).textContent = '0';
            }
            for (const id of ['super-dashboard', 'btn-super-logout', 'btn-toggle-view',
                'branch-inspect-modal', 'edit-owner-modal', 'qr-modal']) hide(id);
        }
        function loginView() {
            hide('view-hub-landing');
            hide('super-dashboard');
            show('super-auth-card');
        }
        function dashboardView() {
            hide('view-hub-landing');
            hide('super-auth-card');
            show('super-dashboard');
            show('btn-super-logout');
            if (hub) {
                show('btn-toggle-view');
                if (node('toggle-view-label')) node('toggle-view-label').textContent = 'Return to Master Hub';
            }
            app.renderDashboard();
        }
        app.loadData = async function (...args) {
            const before = await authorize();
            activeUserId = before.user_id;
            const version = generation;
            try {
                const result = await originalLoad.apply(this, args);
                const after = await authorize();
                if (generation !== version || before.user_id !== after.user_id) {
                    throw new Error('The authenticated account changed. Please sign in again.');
                }
                return result;
            } catch (error) {
                clear();
                loginView();
                throw error;
            }
        };
        app.checkSession = async function () {
            try {
                await app.loadData();
                dashboardView();
                return true;
            } catch (_) {
                clear();
                if (hub) {
                    hide('super-auth-card');
                    show('view-hub-landing');
                } else loginView();
                return false;
            }
        };
        app.init = async function () { await this.checkSession(); };
        app.showDashboardView = async function () {
            if (!await this.checkSession()) loginView();
        };
        app.requestMasterAccess = app.showDashboardView;
        app.showHubView = function () {
            hide('super-auth-card');
            hide('super-dashboard');
            show('view-hub-landing');
            // Navigation visibility is UI state; opening a protected view verifies Auth again.
            if (activeUserId) show('btn-toggle-view');
            else hide('btn-toggle-view');
            if (node('toggle-view-label')) node('toggle-view-label').textContent = 'Open Super Admin Tower';
        };
        app.handleLogin = async function (event) {
            event.preventDefault();
            try {
                const {error} = await client.auth.signInWithPassword({
                    email: node('super-email').value.trim(), password: node('super-password').value
                });
                if (error) throw new Error('Sign-in failed. Check your account and password.');
                if (!await this.checkSession()) throw new Error('A verified Super Admin account is required.');
                node('super-password').value = '';
            } catch (error) {
                try { await root.IronVaultAuth.signOut(client, session, cache); } catch (_) {}
                clear();
                loginView();
                notify(error.message);
            }
        };
        app.logout = async function () {
            clear();
            loginView();
            try { await root.IronVaultAuth.signOut(client, session, cache); }
            catch (error) { notify(error.message); }
        };
        // Do not call Supabase Auth methods synchronously inside its event callback.
        client.auth.onAuthStateChange?.((event, authSession) => {
            if (event === 'SIGNED_OUT' || (event === 'SIGNED_IN' && activeUserId && authSession?.user?.id !== activeUserId)) {
                clear();
                loginView();
            }
        });
    }
    root.IronVaultSuperAdmin = Object.freeze({install});
    if (typeof module === 'object' && module.exports) module.exports = root.IronVaultSuperAdmin;
})(globalThis);
