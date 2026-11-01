<!-- LOVABLE:BEGIN -->
> [!IMPORTANT]
> This project is connected to Lovable. Do not rewrite published Git history.
<!-- LOVABLE:END -->
- Use Supabase browser client with RLS for authenticated workspace CRUD; the database is the permission boundary.
- Keep anonymous signup and teacher bootstrap in server functions; access codes and privileged user creation never reach the browser.
- Keep the signed-in workspace on the public index as a session-aware screen, avoiding duplicate root routes.
- Keep the decorative 3D learning scene client-only on the index route so WebGL never enters SSR.
