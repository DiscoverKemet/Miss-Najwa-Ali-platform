
create type public.app_role as enum ('student', 'teacher_admin');
create type public.student_status as enum ('active', 'disabled');
create type public.assignment_status as enum ('submitted', 'reviewed');

create table public.user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.app_role not null,
  unique (user_id, role)
);
grant select on public.user_roles to authenticated;
grant all on public.user_roles to service_role;
alter table public.user_roles enable row level security;

create or replace function public.has_role(_user_id uuid, _role public.app_role)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.user_roles where user_id = _user_id and role = _role)
$$;
create or replace function public.is_teacher()
returns boolean language sql stable security definer set search_path = public as $$
  select public.has_role(auth.uid(), 'teacher_admin')
$$;
create policy "own roles or teacher" on public.user_roles for select to authenticated
  using (user_id = auth.uid() or public.is_teacher());

create table public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 120),
  description text check (description is null or char_length(description) <= 2000),
  image_path text check (image_path is null or image_path ~ '^groups/[A-Za-z0-9._/-]+$'),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index groups_name_key on public.groups (lower(name));
grant select on public.groups to anon;
grant select, insert, update, delete on public.groups to authenticated;
grant all on public.groups to service_role;
alter table public.groups enable row level security;

create table public.group_access_codes (
  group_id uuid primary key references public.groups(id) on delete cascade,
  access_code text not null check (char_length(access_code) between 4 and 64),
  updated_at timestamptz not null default now()
);
grant select, insert, update, delete on public.group_access_codes to authenticated;
grant all on public.group_access_codes to service_role;
alter table public.group_access_codes enable row level security;
create policy "teacher manages codes" on public.group_access_codes for all to authenticated
  using (public.is_teacher()) with check (public.is_teacher());

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null check (char_length(full_name) between 2 and 120),
  username text not null check (username ~ '^[a-z0-9_.]{3,32}$'),
  created_at timestamptz not null default now()
);
create unique index profiles_username_key on public.profiles (username);
grant select, update on public.profiles to authenticated;
grant all on public.profiles to service_role;
alter table public.profiles enable row level security;

create table public.students (
  id uuid primary key references public.profiles(id) on delete cascade,
  group_id uuid not null references public.groups(id) on delete restrict,
  status public.student_status not null default 'active',
  joined_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index students_group_idx on public.students(group_id);
grant select, update on public.students to authenticated;
grant all on public.students to service_role;
alter table public.students enable row level security;

create or replace function public.my_group_id()
returns uuid language sql stable security definer set search_path = public as $$
  select group_id from public.students where id = auth.uid() and status = 'active'
$$;

create policy "students own row, teacher all" on public.students for select to authenticated
  using (id = auth.uid() or public.is_teacher());
create policy "teacher updates students" on public.students for update to authenticated
  using (public.is_teacher()) with check (public.is_teacher());

create policy "profiles read" on public.profiles for select to authenticated
  using (
    id = auth.uid() or public.is_teacher()
    or exists (select 1 from public.students s where s.id = profiles.id and s.group_id = public.my_group_id())
    or public.has_role(profiles.id, 'teacher_admin')
  );
create policy "teacher updates profiles" on public.profiles for update to authenticated
  using (public.is_teacher()) with check (public.is_teacher());

create policy "groups read" on public.groups for select to anon, authenticated
  using (is_active or public.is_teacher() or id = (select s.group_id from public.students s where s.id = auth.uid()));
create policy "teacher insert groups" on public.groups for insert to authenticated with check (public.is_teacher());
create policy "teacher update groups" on public.groups for update to authenticated using (public.is_teacher()) with check (public.is_teacher());
create policy "teacher delete groups" on public.groups for delete to authenticated using (public.is_teacher());

create table public.classes (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete restrict,
  name text not null check (char_length(name) between 1 and 160),
  starts_at timestamptz not null,
  duration_minutes int not null check (duration_minutes between 5 and 600),
  meeting_url text check (meeting_url is null or meeting_url ~* '^https://[^\s]+$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index classes_group_start_idx on public.classes(group_id, starts_at);
grant select, insert, update, delete on public.classes to authenticated;
grant all on public.classes to service_role;
alter table public.classes enable row level security;
create policy "classes read" on public.classes for select to authenticated
  using (public.is_teacher() or group_id = public.my_group_id());
create policy "teacher insert classes" on public.classes for insert to authenticated with check (public.is_teacher());
create policy "teacher update classes" on public.classes for update to authenticated using (public.is_teacher()) with check (public.is_teacher());
create policy "teacher delete classes" on public.classes for delete to authenticated using (public.is_teacher());

create table public.assignments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  group_id uuid not null references public.groups(id) on delete restrict,
  class_id uuid references public.classes(id) on delete set null,
  notes text check (notes is null or char_length(notes) <= 1000),
  status public.assignment_status not null default 'submitted',
  submitted_at timestamptz,
  created_at timestamptz not null default now()
);
create index assignments_student_idx on public.assignments(student_id, created_at desc);
create index assignments_group_idx on public.assignments(group_id, created_at desc);
create index assignments_class_idx on public.assignments(class_id);
grant select, insert, update, delete on public.assignments to authenticated;
grant all on public.assignments to service_role;
alter table public.assignments enable row level security;
create policy "assignments read" on public.assignments for select to authenticated
  using (student_id = auth.uid() or public.is_teacher());
create policy "student creates own" on public.assignments for insert to authenticated
  with check (student_id = auth.uid() and group_id = public.my_group_id() and status = 'submitted' and submitted_at is null
    and (class_id is null or exists (select 1 from public.classes c where c.id = class_id and c.group_id = public.my_group_id())));
create policy "update assignments" on public.assignments for update to authenticated
  using ((student_id = auth.uid() and submitted_at is null) or public.is_teacher())
  with check ((student_id = auth.uid() and group_id = public.my_group_id()) or public.is_teacher());
create policy "delete assignments" on public.assignments for delete to authenticated
  using (public.is_teacher() or (student_id = auth.uid() and submitted_at is null));

create table public.assignment_images (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.assignments(id) on delete cascade,
  storage_path text not null unique,
  mime_type text not null check (mime_type in ('image/jpeg','image/png','image/webp')),
  size_bytes int not null check (size_bytes > 0 and size_bytes <= 20971520),
  position int not null default 0,
  created_at timestamptz not null default now()
);
create index assignment_images_assignment_idx on public.assignment_images(assignment_id);
grant select, insert, delete on public.assignment_images to authenticated;
grant all on public.assignment_images to service_role;
alter table public.assignment_images enable row level security;
create policy "images read" on public.assignment_images for select to authenticated
  using (public.is_teacher() or exists (select 1 from public.assignments a where a.id = assignment_id and a.student_id = auth.uid()));
create policy "images delete" on public.assignment_images for delete to authenticated
  using (public.is_teacher());

create table public.settings (
  id int primary key default 1 check (id = 1),
  platform_name text not null default 'Miss Najwa Ali' check (char_length(platform_name) between 1 and 80),
  logo_path text check (logo_path is null or logo_path ~ '^branding/[A-Za-z0-9._/-]+$'),
  whatsapp_number text check (whatsapp_number is null or whatsapp_number ~ '^[0-9]{8,15}$'),
  max_image_mb int not null default 5 check (max_image_mb between 1 and 20),
  max_images_per_assignment int not null default 10 check (max_images_per_assignment between 1 and 30),
  allow_student_posts boolean not null default true,
  allow_student_comments boolean not null default true,
  allow_student_signup boolean not null default true,
  updated_at timestamptz not null default now()
);
insert into public.settings (id) values (1);
grant select on public.settings to anon;
grant select, update on public.settings to authenticated;
grant all on public.settings to service_role;
alter table public.settings enable row level security;
create policy "settings read" on public.settings for select to anon, authenticated using (true);
create policy "teacher update settings" on public.settings for update to authenticated using (public.is_teacher()) with check (public.is_teacher());

create table public.posts (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete restrict,
  author_id uuid not null references public.profiles(id) on delete cascade,
  content text not null check (char_length(content) between 1 and 5000),
  is_pinned boolean not null default false,
  is_announcement boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index posts_group_idx on public.posts(group_id, is_pinned desc, created_at desc);
grant select, insert, update, delete on public.posts to authenticated;
grant all on public.posts to service_role;
alter table public.posts enable row level security;
create policy "posts read" on public.posts for select to authenticated
  using (public.is_teacher() or group_id = public.my_group_id());
create policy "posts insert" on public.posts for insert to authenticated
  with check (author_id = auth.uid() and (
    public.is_teacher()
    or (group_id = public.my_group_id() and not is_pinned and not is_announcement
        and (select s.allow_student_posts from public.settings s where s.id = 1))
  ));
create policy "posts update" on public.posts for update to authenticated using (public.is_teacher()) with check (public.is_teacher());
create policy "posts delete" on public.posts for delete to authenticated
  using (public.is_teacher() or (author_id = auth.uid() and group_id = public.my_group_id()));

create table public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  content text not null check (char_length(content) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index comments_post_idx on public.comments(post_id, created_at);
grant select, insert, delete on public.comments to authenticated;
grant all on public.comments to service_role;
alter table public.comments enable row level security;
create policy "comments read" on public.comments for select to authenticated
  using (exists (select 1 from public.posts p where p.id = post_id and (public.is_teacher() or p.group_id = public.my_group_id())));
create policy "comments insert" on public.comments for insert to authenticated
  with check (author_id = auth.uid() and exists (select 1 from public.posts p where p.id = post_id and (
    public.is_teacher() or (p.group_id = public.my_group_id() and (select s.allow_student_comments from public.settings s where s.id = 1)))));
create policy "comments delete" on public.comments for delete to authenticated
  using (public.is_teacher() or (author_id = auth.uid() and exists (select 1 from public.posts p where p.id = post_id and p.group_id = public.my_group_id())));

create table public.activity_logs (
  id bigint generated always as identity primary key,
  actor_id uuid references auth.users(id) on delete set null,
  actor_name text,
  action text not null,
  entity_type text,
  entity_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index activity_logs_created_idx on public.activity_logs(created_at desc);
grant select on public.activity_logs to authenticated;
grant all on public.activity_logs to service_role;
alter table public.activity_logs enable row level security;
create policy "teacher reads logs" on public.activity_logs for select to authenticated using (public.is_teacher());

create or replace function public.write_log(_action text, _entity_type text, _entity_id text, _details jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare _name text;
begin
  select full_name || ' (@' || username || ')' into _name from public.profiles where id = auth.uid();
  insert into public.activity_logs(actor_id, actor_name, action, entity_type, entity_id, details)
  values (auth.uid(), coalesce(_name, 'النظام'), _action, _entity_type, _entity_id, coalesce(_details, '{}'::jsonb));
end $$;
revoke all on function public.write_log(text,text,text,jsonb) from public, anon, authenticated;

create or replace function public.log_session_event(_action text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or _action not in ('login','logout') then raise exception 'invalid'; end if;
  perform public.write_log(_action, 'auth', auth.uid()::text, '{}'::jsonb);
end $$;
revoke all on function public.log_session_event(text) from public, anon;
grant execute on function public.log_session_event(text) to authenticated;

create or replace function public.audit_trigger()
returns trigger language plpgsql security definer set search_path = public as $$
declare _n jsonb; _o jsonb; _row jsonb; _id text; _details jsonb := '{}'::jsonb; _action text;
begin
  _action := lower(TG_OP);
  _n := case when TG_OP = 'DELETE' then null else to_jsonb(new) end;
  _o := case when TG_OP = 'INSERT' then null else to_jsonb(old) end;
  _row := coalesce(_n, _o);
  _id := _row->>coalesce(TG_ARGV[0], 'id');
  if TG_TABLE_NAME = 'groups' then
    _details := jsonb_build_object('name', _row->>'name');
    if TG_OP = 'UPDATE' and (_o->>'is_active') is distinct from (_n->>'is_active') then
      _action := case when (_n->>'is_active')::boolean then 'activate' else 'deactivate' end; end if;
  elsif TG_TABLE_NAME = 'group_access_codes' then
    _action := 'code_change';
  elsif TG_TABLE_NAME = 'classes' then
    _details := jsonb_build_object('name', _row->>'name');
    if TG_OP = 'UPDATE' and (_o->>'meeting_url') is distinct from (_n->>'meeting_url') then _action := 'link_change'; end if;
  elsif TG_TABLE_NAME = 'students' then
    if TG_OP = 'UPDATE' and (_o->>'group_id') is distinct from (_n->>'group_id') then
      _action := 'transfer'; _details := jsonb_build_object('from', _o->>'group_id', 'to', _n->>'group_id');
    elsif TG_OP = 'UPDATE' and (_o->>'status') is distinct from (_n->>'status') then
      _action := 'status_' || (_n->>'status');
    elsif TG_OP = 'UPDATE' then return new;
    end if;
  elsif TG_TABLE_NAME = 'assignments' then
    if TG_OP = 'INSERT' then return new; end if;
    if TG_OP = 'UPDATE' then
      if _o->>'submitted_at' is null and _n->>'submitted_at' is not null then _action := 'submit';
      elsif (_o->>'status') is distinct from (_n->>'status') then _action := 'status_' || (_n->>'status');
      else return new; end if;
    end if;
  elsif TG_TABLE_NAME = 'posts' then
    _details := jsonb_build_object('group_id', _row->>'group_id');
    if TG_OP = 'UPDATE' and (_o->>'is_pinned') is distinct from (_n->>'is_pinned') then
      _action := case when (_n->>'is_pinned')::boolean then 'pin' else 'unpin' end; end if;
  end if;
  perform public.write_log(_action, TG_TABLE_NAME, _id, _details);
  if TG_OP = 'DELETE' then return old; end if;
  return new;
end $$;

create trigger audit_groups after insert or update or delete on public.groups for each row execute function public.audit_trigger();
create trigger audit_codes after insert or update on public.group_access_codes for each row execute function public.audit_trigger('group_id');
create trigger audit_classes after insert or update or delete on public.classes for each row execute function public.audit_trigger();
create trigger audit_students after insert or update or delete on public.students for each row execute function public.audit_trigger();
create trigger audit_assignments after insert or update or delete on public.assignments for each row execute function public.audit_trigger();
create trigger audit_posts after insert or update or delete on public.posts for each row execute function public.audit_trigger();
create trigger audit_comments after delete on public.comments for each row execute function public.audit_trigger();
create trigger audit_settings after update on public.settings for each row execute function public.audit_trigger();

create or replace function public.touch_updated_at() returns trigger language plpgsql set search_path = public as $$
begin new.updated_at := now(); return new; end $$;
create trigger t_groups before update on public.groups for each row execute function public.touch_updated_at();
create trigger t_codes before update on public.group_access_codes for each row execute function public.touch_updated_at();
create trigger t_classes before update on public.classes for each row execute function public.touch_updated_at();
create trigger t_students before update on public.students for each row execute function public.touch_updated_at();
create trigger t_posts before update on public.posts for each row execute function public.touch_updated_at();
create trigger t_settings before update on public.settings for each row execute function public.touch_updated_at();

create policy "assignments: student uploads to own folder" on storage.objects for insert to authenticated
  with check (bucket_id = 'assignments' and (storage.foldername(name))[1] = auth.uid()::text and public.my_group_id() is not null
    and lower(storage.extension(name)) in ('jpg','jpeg','png','webp'));
create policy "assignments: read own or teacher" on storage.objects for select to authenticated
  using (bucket_id = 'assignments' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_teacher()));
create policy "assignments: delete own unlinked or teacher" on storage.objects for delete to authenticated
  using (bucket_id = 'assignments' and (public.is_teacher() or (
    (storage.foldername(name))[1] = auth.uid()::text
    and not exists (select 1 from public.assignment_images i where i.storage_path = storage.objects.name))));

create policy "media: anyone reads" on storage.objects for select to anon, authenticated
  using (bucket_id = 'media');
create policy "media: teacher upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'media' and public.is_teacher() and lower(storage.extension(name)) in ('jpg','jpeg','png','webp'));
create policy "media: teacher update" on storage.objects for update to authenticated
  using (bucket_id = 'media' and public.is_teacher());
create policy "media: teacher delete" on storage.objects for delete to authenticated
  using (bucket_id = 'media' and public.is_teacher());
