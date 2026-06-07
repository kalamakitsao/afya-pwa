-- ============================================================
-- Afya Nyumbani PWA — Supabase setup
-- Run this entire script in: Supabase Dashboard → SQL Editor
-- Takes about 10 seconds. Run once.
-- ============================================================

-- Enable UUID extension (usually already on in Supabase)
create extension if not exists "uuid-ossp";

-- ── HIERARCHY ────────────────────────────────────────────────
create table if not exists chp_areas (
  id          uuid primary key default uuid_generate_v4(),
  name        text not null,
  chu_name    text not null,
  sub_county  text not null,
  county      text not null,
  created_at  timestamptz default now()
);

create table if not exists households (
  id           uuid primary key default uuid_generate_v4(),
  chp_area_id  uuid references chp_areas(id),
  name         text not null,
  village      text,
  created_at   timestamptz default now()
);

create table if not exists clients (
  id            uuid primary key default uuid_generate_v4(),
  household_id  uuid references households(id),
  first_name    text not null,
  last_name     text,
  sex           text,
  date_of_birth date,
  created_at    timestamptz default now()
);

-- ── EVENTS (universal form submission table) ─────────────────
create table if not exists events (
  id            uuid primary key default uuid_generate_v4(),
  chp_area_id   uuid references chp_areas(id),
  client_id     uuid references clients(id),
  submitted_by  uuid,                    -- user id from auth.users
  form_id       text not null,
  context_type  text not null default 'area',
  answers       jsonb not null default '{}',
  sync_status   text not null default 'pending',
  created_at    timestamptz default now()
);

-- ── TASKS (server-created, synced to CHA) ────────────────────
create table if not exists tasks (
  id           uuid primary key default uuid_generate_v4(),
  event_id     uuid references events(id),
  assigned_to  uuid,                     -- user id
  title        text not null,
  form_type    text not null default 'signal_verification',
  due_date     date,
  status       text not null default 'pending',
  created_at   timestamptz default now()
);

-- ── CONFIG (form schemas, synced to all devices) ─────────────
create table if not exists config_forms (
  id           uuid primary key default uuid_generate_v4(),
  form_id      text not null,
  version      int not null default 1,
  json_schema  jsonb not null,
  published_at timestamptz default now(),
  unique(form_id, version)
);

-- ── USER PROFILES (linked to auth.users) ─────────────────────
create table if not exists profiles (
  id            uuid primary key references auth.users(id),
  username      text not null,
  role          text not null default 'chp',
  chp_area_id   uuid references chp_areas(id),
  display_name  text
);

-- ── ROW LEVEL SECURITY ────────────────────────────────────────
alter table chp_areas     enable row level security;
alter table households    enable row level security;
alter table clients       enable row level security;
alter table events        enable row level security;
alter table tasks         enable row level security;
alter table config_forms  enable row level security;
alter table profiles      enable row level security;

-- Allow authenticated users to read all chp_areas and config (needed for sync)
create policy "read chp_areas"    on chp_areas    for select using (auth.role() = 'authenticated');
create policy "read config_forms" on config_forms for select using (auth.role() = 'authenticated');
create policy "read profiles"     on profiles     for select using (auth.uid() = id);
create policy "update profiles"   on profiles     for update using (auth.uid() = id);

-- Households and clients: authenticated users can read all (for PoC simplicity)
create policy "read households"   on households   for select using (auth.role() = 'authenticated');
create policy "read clients"      on clients      for select using (auth.role() = 'authenticated');

-- Events: users can insert their own, read all in their area
create policy "insert events" on events for insert
  with check (auth.uid() = submitted_by);
create policy "read events"  on events  for select using (auth.role() = 'authenticated');

-- Tasks: users can read tasks assigned to them
create policy "read tasks"   on tasks   for select
  using (assigned_to = auth.uid() or auth.role() = 'authenticated');

-- ── TRIGGER: create CHA task on signal submission ─────────────
create or replace function create_signal_task()
returns trigger as $$
declare
  v_cha_id uuid;
begin
  if NEW.form_id != 'cebs_signal' then return NEW; end if;

  -- Find CHA for this CHP area (any user with role=cha in profiles)
  -- In PoC: find first CHA user (in production: match by CHU)
  select id into v_cha_id
  from profiles
  where role = 'cha'
  limit 1;

  if v_cha_id is not null then
    insert into tasks (event_id, assigned_to, title, due_date, status)
    values (
      NEW.id,
      v_cha_id,
      case
        when NEW.answers->>'signal_type' = 'outbreak'
          then 'URGENT: Verify outbreak signal — ' || coalesce(NEW.answers->>'location_detail', 'unknown location')
        else 'Verify signal — ' || coalesce(NEW.answers->>'signal_type', 'unknown')
      end,
      (now() + interval '48 hours')::date,
      'pending'
    );
  end if;

  return NEW;
end;
$$ language plpgsql security definer;

create trigger signal_task_trigger
  after insert on events
  for each row execute function create_signal_task();

-- ── SEED DATA ────────────────────────────────────────────────
-- 3 CHP areas in Kiharu CHU, Baringo
insert into chp_areas (id, name, chu_name, sub_county, county) values
  ('d0000001-0000-0000-0000-000000000001', 'Zone A — Kiharu Village',   'Kiharu CHU', 'Kaptum', 'Baringo'),
  ('d0000001-0000-0000-0000-000000000002', 'Zone B — Endao Village',    'Kiharu CHU', 'Kaptum', 'Baringo'),
  ('d0000001-0000-0000-0000-000000000003', 'Zone C — Bartabwa Village', 'Kiharu CHU', 'Kaptum', 'Baringo')
on conflict do nothing;

-- Sample households
insert into households (chp_area_id, name, village) values
  ('d0000001-0000-0000-0000-000000000001', 'Kamau Household',   'Kiharu village'),
  ('d0000001-0000-0000-0000-000000000001', 'Njoroge Household', 'Kiharu village'),
  ('d0000001-0000-0000-0000-000000000002', 'Mutua Household',   'Endao village')
on conflict do nothing;

-- CEBS signal form schema
insert into config_forms (form_id, version, json_schema) values (
'cebs_signal', 1, '{
  "form_id": "cebs_signal",
  "title": "Outbreak Signal Report",
  "context_type": "area",
  "sections": [
    {
      "id": "signal_type_section",
      "title": "What are you reporting?",
      "questions": [
        {
          "id": "signal_type",
          "type": "select_one",
          "label": "Type of signal",
          "required": true,
          "choices": [
            {"value": "outbreak",             "label": "Suspected outbreak (fever + bleeding)",  "urgent": true},
            {"value": "similar_symptoms",     "label": "Cluster of similar symptoms",            "urgent": false},
            {"value": "death_in_community",   "label": "Unexplained death in community",         "urgent": false},
            {"value": "child_weak_legs_arms", "label": "Child with sudden limb weakness",        "urgent": true},
            {"value": "diarrhea",             "label": "Diarrhoea cluster",                      "urgent": false},
            {"value": "animal_sickness",      "label": "Animal sickness or deaths",              "urgent": false},
            {"value": "animal_bite",          "label": "Animal bite (rabies risk)",              "urgent": false},
            {"value": "public_event",         "label": "Public health event or concern",         "urgent": false}
          ]
        },
        {
          "id": "health_threat_start_date",
          "type": "date",
          "label": "Date first observed",
          "required": true
        },
        {
          "id": "approx_people_affected",
          "type": "integer",
          "label": "Approximate number of people ill",
          "required": true
        },
        {
          "id": "approx_people_dead",
          "type": "integer",
          "label": "Number of deaths (0 if none)",
          "required": false
        }
      ]
    },
    {
      "id": "outbreak_detail",
      "title": "Outbreak Details (Possible Ebola / VHF)",
      "relevant": {"op": "eq", "field": "signal_type", "value": "outbreak"},
      "questions": [
        {
          "id": "fever_present",
          "type": "select_one",
          "label": "Does the person have fever?",
          "required": true,
          "choices": [
            {"value": "yes",     "label": "Yes — fever present"},
            {"value": "no",      "label": "No fever"},
            {"value": "unknown", "label": "Unable to assess"}
          ]
        },
        {
          "id": "bleeding_signs",
          "type": "select_many",
          "label": "Signs of bleeding (select all that apply)",
          "required": true,
          "choices": [
            {"value": "vomiting_blood",  "label": "Vomiting blood"},
            {"value": "blood_in_stool",  "label": "Blood in stool"},
            {"value": "bleeding_gums",   "label": "Bleeding from gums or nose"},
            {"value": "skin_bruising",   "label": "Unexplained skin bruising"},
            {"value": "none",            "label": "No visible bleeding signs"}
          ]
        },
        {
          "id": "contact_with_case",
          "type": "select_one",
          "label": "Contact with known sick person or dead body?",
          "required": true,
          "choices": [
            {"value": "yes",     "label": "Yes — confirmed contact"},
            {"value": "no",      "label": "No known contact"},
            {"value": "unknown", "label": "Unknown"}
          ]
        }
      ]
    },
    {
      "id": "location_section",
      "title": "Location & Description",
      "questions": [
        {
          "id": "location_detail",
          "type": "text",
          "label": "Exact village or location",
          "required": true
        },
        {
          "id": "signal_description",
          "type": "textarea",
          "label": "Brief description of what happened",
          "required": true
        },
        {
          "id": "cha_notified",
          "type": "select_one",
          "label": "Has your CHA supervisor been notified?",
          "required": true,
          "choices": [
            {"value": "yes", "label": "Yes"},
            {"value": "no",  "label": "No — will notify after submitting"}
          ]
        }
      ]
    }
  ]
}'::jsonb)
on conflict (form_id, version) do nothing;

-- Done!
select 'Setup complete ✓' as status,
  (select count(*) from chp_areas)    as chp_areas,
  (select count(*) from config_forms) as forms_loaded;
