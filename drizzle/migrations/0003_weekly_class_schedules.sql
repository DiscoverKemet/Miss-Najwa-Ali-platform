create table public.class_schedules (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete restrict,
  name text not null check (char_length(name) between 1 and 160),
  weekday smallint not null check (weekday between 0 and 6),
  start_time time not null,
  duration_minutes int not null check (duration_minutes between 5 and 600),
  meeting_url text check (meeting_url is null or meeting_url ~* '^https://[^\s]+$'),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index class_schedules_group_idx on public.class_schedules(group_id, weekday);

grant select, insert, update, delete on public.class_schedules to authenticated;
grant all on public.class_schedules to service_role;
alter table public.class_schedules enable row level security;

create policy "schedules read" on public.class_schedules for select to authenticated
  using (public.is_teacher() or group_id = public.my_group_id());
create policy "teacher insert schedules" on public.class_schedules for insert to authenticated
  with check (public.is_teacher());
create policy "teacher update schedules" on public.class_schedules for update to authenticated
  using (public.is_teacher()) with check (public.is_teacher());
create policy "teacher delete schedules" on public.class_schedules for delete to authenticated
  using (public.is_teacher());

create trigger t_class_schedules before update on public.class_schedules
  for each row execute function public.touch_updated_at();

alter table public.classes add column schedule_id uuid references public.class_schedules(id) on delete set null;
alter table public.classes add column is_cancelled boolean not null default false;
alter table public.classes add column cancel_note text;
create index classes_schedule_idx on public.classes(schedule_id);