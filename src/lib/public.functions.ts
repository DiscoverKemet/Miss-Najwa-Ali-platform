import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { USERNAME_RE, normalizeUsername, usernameToEmail } from "./usernames";

function teacherConfigs() {
  const list: { username: string; password: string; name: string }[] = [];
  for (const n of [1, 2]) {
    const username = process.env[`TEACHER_${n}_USERNAME`];
    const password = process.env[`TEACHER_${n}_PASSWORD`];
    const name = process.env[`TEACHER_${n}_NAME`] || "Miss Najwa Ali";
    if (username && password && USERNAME_RE.test(normalizeUsername(username)) && password.length >= 8) {
      list.push({ username: normalizeUsername(username), password, name });
    }
  }
  return list;
}

const signupSchema = z
  .object({
    fullName: z.string().trim().min(2, "الاسم قصير جداً").max(120),
    username: z
      .string()
      .transform(normalizeUsername)
      .refine((v) => USERNAME_RE.test(v), "اسم المستخدم: 3-32 حرفاً إنجليزياً صغيراً أو أرقام أو _ ."),
    password: z.string().min(8, "كلمة المرور 8 أحرف على الأقل").max(72),
    confirm: z.string(),
    groupId: z.string().uuid(),
    accessCode: z.string().trim().min(1).max(64),
  })
  .refine((d) => d.password === d.confirm, { message: "كلمتا المرور غير متطابقتين", path: ["confirm"] });

type SignupResult = { ok: true } | { ok: false; code: string; message: string };

export const signUpStudent = createServerFn({ method: "POST" })
  .inputValidator((d: unknown) => signupSchema.parse(d))
  .handler(async ({ data }): Promise<SignupResult> => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

    const { data: settings } = await supabaseAdmin.from("settings").select("allow_student_signup").eq("id", 1).single();
    if (!settings?.allow_student_signup) return { ok: false, code: "closed", message: "التسجيل مغلق حالياً." };

    if (teacherConfigs().some((t) => t.username === data.username))
      return { ok: false, code: "username", message: "اسم المستخدم غير متاح." };

    const { data: group } = await supabaseAdmin.from("groups").select("id,is_active").eq("id", data.groupId).maybeSingle();
    if (!group || !group.is_active) return { ok: false, code: "inactive", message: "هذه المجموعة غير متاحة حالياً." };

    const { data: code } = await supabaseAdmin
      .from("group_access_codes").select("access_code").eq("group_id", data.groupId).maybeSingle();
    if (!code || code.access_code !== data.accessCode) return { ok: false, code: "code", message: "الكود غير صحيح." };

    const { data: existing } = await supabaseAdmin.from("profiles").select("id").eq("username", data.username).maybeSingle();
    if (existing) return { ok: false, code: "username", message: "اسم المستخدم مستخدم بالفعل." };

    const { data: created, error } = await supabaseAdmin.auth.admin.createUser({
      email: usernameToEmail(data.username),
      password: data.password,
      email_confirm: true,
      user_metadata: { full_name: data.fullName, username: data.username },
    });
    if (error || !created.user) {
      return { ok: false, code: "auth", message: error?.message?.includes("already") ? "اسم المستخدم مستخدم بالفعل." : "تعذر إنشاء الحساب." };
    }
    const uid = created.user.id;
    const p = await supabaseAdmin.from("profiles").insert({ id: uid, full_name: data.fullName, username: data.username });
    const r = await supabaseAdmin.from("user_roles").insert({ user_id: uid, role: "student" });
    const s = await supabaseAdmin.from("students").insert({ id: uid, group_id: data.groupId });
    if (p.error || r.error || s.error) {
      await supabaseAdmin.auth.admin.deleteUser(uid);
      return { ok: false, code: "db", message: "تعذر إنشاء الحساب، حاول مرة أخرى." };
    }
    return { ok: true };
  });

/** One-time teacher bootstrap: never callable without a separately configured secret. */
export const ensureTeacherAccounts = createServerFn({ method: "POST" })
  .inputValidator((d: unknown) => z.object({ token: z.string().min(32) }).parse(d))
  .handler(async ({ data }) => {
    const secret = process.env['TEACHER_BOOTSTRAP_SECRET'];
    if (!secret || secret.length < 32) throw new Error("Bootstrap unavailable");
    const { timingSafeEqual } = await import("node:crypto");
    const supplied = Buffer.from(data.token);
    const expected = Buffer.from(secret);
    if (supplied.length !== expected.length || !timingSafeEqual(supplied, expected)) throw new Error("Unauthorized");
    const configs = teacherConfigs();
    if (configs.length !== 2 || configs[0]?.username === configs[1]?.username) throw new Error("Configure two distinct teacher accounts");
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data: existing } = await supabaseAdmin.from("user_roles").select("id").eq("role", "teacher_admin").limit(1);
    if (existing?.length) throw new Error("Bootstrap already completed");
    let created = 0;
    for (const t of configs) {
      const { data: profile } = await supabaseAdmin.from("profiles").select("id").eq("username", t.username).maybeSingle();
      if (profile) throw new Error("Username unavailable");
      const { data: result, error } = await supabaseAdmin.auth.admin.createUser({
        email: usernameToEmail(t.username), password: t.password, email_confirm: true,
        user_metadata: { full_name: t.name, username: t.username },
      });
      if (error || !result.user) throw new Error("Could not create teacher account");
      const uid = result.user.id;
      const p = await supabaseAdmin.from("profiles").insert({ id: uid, full_name: t.name, username: t.username });
      const r = p.error ? p : await supabaseAdmin.from("user_roles").insert({ user_id: uid, role: "teacher_admin" });
      if (r.error) { await supabaseAdmin.auth.admin.deleteUser(uid); throw new Error("Could not save teacher role"); }
      created++;
    }
    return { created };
  });

/** Creates the configured teacher account on first login, only when the supplied credentials match the server secrets. */
export const ensureConfiguredTeacher = createServerFn({ method: "POST" })
  .inputValidator((d: unknown) => z.object({ username: z.string().max(64), password: z.string().max(72) }).parse(d))
  .handler(async ({ data }) => {
    const { timingSafeEqual } = await import("node:crypto");
    const eq = (a: string, b: string) => { const x = Buffer.from(a), y = Buffer.from(b); return x.length === y.length && timingSafeEqual(x, y); };
    const t = teacherConfigs().find((c) => c.username === normalizeUsername(data.username));
    if (!t || !eq(data.password, t.password)) return { ok: false };
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data: profile } = await supabaseAdmin.from("profiles").select("id").eq("username", t.username).maybeSingle();
    if (profile) return { ok: true };
    const { data: result, error } = await supabaseAdmin.auth.admin.createUser({
      email: usernameToEmail(t.username), password: t.password, email_confirm: true,
      user_metadata: { full_name: t.name, username: t.username },
    });
    if (error || !result.user) return { ok: false };
    const uid = result.user.id;
    const p = await supabaseAdmin.from("profiles").insert({ id: uid, full_name: t.name, username: t.username });
    const r = p.error ? p : await supabaseAdmin.from("user_roles").insert({ user_id: uid, role: "teacher_admin" });
    if (r.error) { await supabaseAdmin.auth.admin.deleteUser(uid); return { ok: false }; }
    return { ok: true };
  });
