-- 神憑 KAMIGAKARI 奉納番付 — Supabase setup
-- Supabase の「SQL Editor」にこのファイルの中身を貼り付けて「Run」してください。
-- 何度実行しても壊れないように書いてあります。

create table if not exists public.banzuke (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  name        text        not null check (char_length(name) between 1 and 12),
  diff        text        not null check (diff in ('roku','hachi')),
  score       integer     not null check (score >= 0),
  max_combo   integer     not null check (max_combo >= 0),
  acc         numeric(5,2) not null check (acc between 0 and 100),
  heads       smallint    not null check (heads between 0 and 8),
  defeated    boolean     not null default false
);
create index if not exists banzuke_diff_score on public.banzuke (diff, score desc, created_at);

-- 誰でも読める。直接の書き込み・更新・削除は不可（書き込みは下の関数だけ）
alter table public.banzuke enable row level security;
drop policy if exists "banzuke readable by everyone" on public.banzuke;
create policy "banzuke readable by everyone" on public.banzuke
  for select to anon, authenticated using (true);
revoke insert, update, delete on public.banzuke from anon, authenticated;

-- 奉納（スコア登録）。値の範囲と名前を検証してから登録し、その部での順位を返す
create or replace function public.submit_score(
  p_name text, p_diff text, p_score integer, p_max_combo integer,
  p_acc numeric, p_heads integer, p_defeated boolean
) returns table (id bigint, rank bigint)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_name  text;
  v_id    bigint;
  v_max   integer;
  v_combo integer;
  v_recent integer;
begin
  v_name := btrim(regexp_replace(coalesce(p_name, ''), '[[:space:]　]+', ' ', 'g'));
  if char_length(v_name) < 1 or char_length(v_name) > 12 then
    raise exception 'name length';
  end if;
  if v_name ~* '(https?:|www\.|死ね|殺す|ころす|ちんこ|まんこ|うんこ|セックス|fuck|shit|bitch)' then
    raise exception 'name not allowed';
  end if;

  -- 理論上の上限（譜面のノーツ数から計算した値に余裕を持たせたもの）
  if p_diff = 'roku' then v_max := 300000; v_combo := 160;
  elsif p_diff = 'hachi' then v_max := 550000; v_combo := 320;
  else raise exception 'bad diff';
  end if;
  if p_score < 0 or p_score > v_max or p_max_combo < 0 or p_max_combo > v_combo
     or p_acc < 0 or p_acc > 100 or p_heads < 0 or p_heads > 8 then
    raise exception 'out of range';
  end if;

  -- 連打防止: 全体で1分あたり30件まで
  select count(*) into v_recent from public.banzuke b where b.created_at > now() - interval '1 minute';
  if v_recent >= 30 then
    raise exception 'busy';
  end if;

  insert into public.banzuke (name, diff, score, max_combo, acc, heads, defeated)
  values (v_name, p_diff, p_score, p_max_combo, round(p_acc, 2), p_heads, coalesce(p_defeated, false))
  returning public.banzuke.id into v_id;

  return query
    select v_id, (select count(*) + 1 from public.banzuke b where b.diff = p_diff and b.score > p_score);
end;
$$;

revoke all on function public.submit_score(text, text, integer, integer, numeric, integer, boolean) from public;
grant execute on function public.submit_score(text, text, integer, integer, numeric, integer, boolean) to anon, authenticated;

-- 不適切な名前を消すとき（Table Editor から行を削除してもOK）:
-- delete from public.banzuke where id = 123;
