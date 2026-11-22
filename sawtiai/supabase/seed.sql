-- Initial structure only. NO subjects, chapters, questions or files are seeded:
-- official curriculum content must be entered and verified by an administrator.
-- The stage/grade/branch layout below reflects the commonly used Iraqi structure
-- and is flagged as "needs verification" in app_settings; adjust it from the
-- admin dashboard if the Ministry structure differs.

insert into public.academic_stages (code, name_ar, name_en, sort_order) values
  ('intermediate', 'المرحلة المتوسطة', 'Intermediate', 1),
  ('preparatory',  'المرحلة الإعدادية', 'Preparatory', 2)
on conflict (code) do nothing;

insert into public.grades (stage_id, code, name_ar, name_en, has_branches, sort_order)
select s.id, g.code, g.name_ar, g.name_en, g.has_branches, g.sort_order
from (values
  ('intermediate', 'grade_7',  'الأول المتوسط',   'First Intermediate',  false, 1),
  ('intermediate', 'grade_8',  'الثاني المتوسط',  'Second Intermediate', false, 2),
  ('intermediate', 'grade_9',  'الثالث المتوسط',  'Third Intermediate',  false, 3),
  ('preparatory',  'grade_10', 'الرابع الإعدادي', 'Fourth Preparatory',  true,  4),
  ('preparatory',  'grade_11', 'الخامس الإعدادي', 'Fifth Preparatory',   true,  5),
  ('preparatory',  'grade_12', 'السادس الإعدادي', 'Sixth Preparatory',   true,  6)
) as g(stage_code, code, name_ar, name_en, has_branches, sort_order)
join public.academic_stages s on s.code = g.stage_code
on conflict (code) do nothing;

insert into public.academic_branches (grade_id, code, name_ar, name_en, sort_order)
select gr.id, b.code, b.name_ar, b.name_en, b.sort_order
from (values
  ('grade_10', 'scientific', 'العلمي',          'Scientific',            1),
  ('grade_10', 'literary',   'الأدبي',          'Literary',              2),
  ('grade_11', 'applied',    'العلمي التطبيقي', 'Scientific - Applied',   1),
  ('grade_11', 'biological', 'العلمي الإحيائي', 'Scientific - Biological', 2),
  ('grade_11', 'literary',   'الأدبي',          'Literary',              3),
  ('grade_12', 'applied',    'العلمي التطبيقي', 'Scientific - Applied',   1),
  ('grade_12', 'biological', 'العلمي الإحيائي', 'Scientific - Biological', 2),
  ('grade_12', 'literary',   'الأدبي',          'Literary',              3)
) as b(grade_code, code, name_ar, name_en, sort_order)
join public.grades gr on gr.code = b.grade_code
on conflict (grade_id, code) do nothing;

insert into public.academic_years (label, starts_on, ends_on, is_current) values
  ('2026-2027', '2026-09-01', '2027-08-31', true)
on conflict (label) do nothing;

insert into public.library_categories (code, name_ar, sort_order) values
  ('books', 'الكتب المنهجية', 1),
  ('notes', 'ملازم', 2),
  ('summaries', 'ملخصات', 3),
  ('worksheets', 'أوراق عمل', 4),
  ('images', 'صور', 5),
  ('supplementary', 'مواد إضافية', 6)
on conflict (code) do nothing;

insert into public.app_settings (key, value, is_public) values
  ('telegram_channel_url', 'null', true),
  ('support_contact', 'null', true),
  ('academic_structure_verified', 'false', false),
  ('governorates', '["بغداد","البصرة","نينوى","أربيل","النجف","كربلاء","بابل","ذي قار","ديالى","الأنبار","كركوك","صلاح الدين","واسط","ميسان","المثنى","الديوانية","دهوك","السليمانية","حلبجة"]', true)
on conflict (key) do nothing;
