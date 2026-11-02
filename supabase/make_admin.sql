-- Run in Supabase › SQL Editor after creating your user in Authentication › Users.
-- Replace the email below.
update public.profiles
   set role = 'admin'
 where id = (select id from auth.users where email = 'you@example.com');

-- If the profile row does not exist yet (user created before the migration ran):
insert into public.profiles (id, role)
select id, 'admin' from auth.users where email = 'you@example.com'
on conflict (id) do update set role = 'admin';
