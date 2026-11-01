import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";

const Input = z.object({
  messages: z
    .array(z.object({ role: z.enum(["user", "assistant"]), content: z.string().min(1).max(4000) }))
    .min(1)
    .max(30),
  timezone: z.string().max(64).optional(),
});

export const askTeacherAssistant = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((d: unknown) => Input.parse(d))
  .handler(async ({ data, context }) => {
    const sb = context.supabase;
    const { data: isTeacher } = await sb.rpc("has_role", { _user_id: context.userId, _role: "teacher_admin" });
    if (!isTeacher) throw new Error("هذه الميزة للمعلمين فقط");
    const apiKey = process.env["LOVABLE_API_KEY"];
    if (!apiKey) return { ok: false as const, message: "المساعد غير مهيأ حالياً" };

    const { createOpenAI } = await import("@ai-sdk/openai");
    const { streamText, tool, stepCountIs } = await import("ai");

    const [groups, classes, students, assignments] = await Promise.all([
      sb.from("groups").select("id,name,is_active"),
      sb.from("classes").select("id,group_id,name,starts_at,duration_minutes,meeting_url,is_cancelled,schedule_id").gte("starts_at", new Date(Date.now() - 7 * 864e5).toISOString()).order("starts_at").limit(80),
      sb.from("students").select("id,group_id,status"),
      sb.from("assignments").select("id,status,submitted_at").limit(500),
    ]);
    const snapshot = {
      now: new Date().toISOString(),
      teacherTimezone: data.timezone ?? "Africa/Cairo",
      groups: groups.data ?? [],
      upcomingAndRecentClasses: classes.data ?? [],
      studentsPerGroup: (groups.data ?? []).map((g) => ({ group: g.name, count: (students.data ?? []).filter((s) => s.group_id === g.id).length })),
      assignments: { total: assignments.data?.length ?? 0, reviewed: (assignments.data ?? []).filter((a) => a.status === "reviewed").length },
    };

    const done: string[] = [];
    const fail = (m: string) => ({ ok: false, error: m });
    const tools = {
      create_class: tool({
        description: "إنشاء حصة واحدة لمجموعة. starts_at بصيغة ISO مع المنطقة الزمنية.",
        inputSchema: z.object({ group_id: z.string().uuid(), name: z.string().min(1).max(160), starts_at: z.string(), duration_minutes: z.number().int().min(5).max(600), meeting_url: z.string().url().startsWith("https://").nullable() }),
        execute: async (a) => { const { error } = await sb.from("classes").insert({ ...a, starts_at: new Date(a.starts_at).toISOString() }); if (error) return fail(error.message); done.push(`أُنشئت حصة: ${a.name}`); return { ok: true }; },
      }),
      reschedule_class: tool({
        description: "تأجيل أو تغيير موعد/رابط/مدة حصة واحدة فقط (هذا الأسبوع).",
        inputSchema: z.object({ class_id: z.string().uuid(), starts_at: z.string().nullable(), duration_minutes: z.number().int().min(5).max(600).nullable(), meeting_url: z.string().url().startsWith("https://").nullable() }),
        execute: async (a) => { const patch: { starts_at?: string; duration_minutes?: number; meeting_url?: string } = {}; if (a.starts_at) patch.starts_at = new Date(a.starts_at).toISOString(); if (a.duration_minutes) patch.duration_minutes = a.duration_minutes; if (a.meeting_url) patch.meeting_url = a.meeting_url; const { error } = await sb.from("classes").update(patch).eq("id", a.class_id); if (error) return fail(error.message); done.push("عُدّل موعد حصة"); return { ok: true }; },
      }),
      cancel_class: tool({
        description: "إلغاء حصة واحدة (أو إعادتها) دون حذفها.",
        inputSchema: z.object({ class_id: z.string().uuid(), cancelled: z.boolean(), note: z.string().max(300).nullable() }),
        execute: async (a) => { const { error } = await sb.from("classes").update({ is_cancelled: a.cancelled, cancel_note: a.cancelled ? a.note : null }).eq("id", a.class_id); if (error) return fail(error.message); done.push(a.cancelled ? "أُلغيت حصة" : "أُعيدت حصة"); return { ok: true }; },
      }),
      delete_class: tool({
        description: "حذف حصة واحدة نهائياً. استخدمها فقط إذا طلبت المعلمة الحذف صراحة.",
        inputSchema: z.object({ class_id: z.string().uuid() }),
        execute: async (a) => { const { error } = await sb.from("classes").delete().eq("id", a.class_id); if (error) return fail(error.message); done.push("حُذفت حصة"); return { ok: true }; },
      }),
      create_post: tool({
        description: "نشر إعلان في مجتمع مجموعة.",
        inputSchema: z.object({ group_id: z.string().uuid(), content: z.string().min(1).max(3000), pinned: z.boolean() }),
        execute: async (a) => { const { error } = await sb.from("posts").insert({ group_id: a.group_id, content: a.content, author_id: context.userId, is_pinned: a.pinned, is_announcement: true }); if (error) return fail(error.message); done.push("نُشر إعلان"); return { ok: true }; },
      }),
    };

    const provider = createOpenAI({
      baseURL: "https://ai.gateway.lovable.dev/v1",
      apiKey,
      headers: { "Lovable-API-Key": apiKey, "X-Lovable-AIG-SDK": "vercel-ai-sdk" },
    });
    try {
      const result = streamText({
        model: provider.responses("openai/gpt-6-astra"),
        system: `أنت مساعد المعلمة في منصة Miss Najwa Ali التعليمية. تحدث بالعربية بإيجاز وود. تساعد في إدارة الحصص (إنشاء، تأجيل، إلغاء، حذف)، كتابة الإعلانات، وتلخيص حال المنصة. نفّذ الإجراءات بالأدوات فقط عندما يكون الطلب واضحاً، واسأل إذا كانت المجموعة أو الحصة أو الوقت غير واضح. لا تخترع معرفات؛ استخدم المعرفات من البيانات. اكتب الأوقات بتوقيت المعلمة. لا تذكر المعرفات للمعلمة.\nبيانات المنصة الحالية:\n${JSON.stringify(snapshot)}`,
        messages: data.messages,
        tools,
        stopWhen: stepCountIs(6),
        providerOptions: { openai: { store: false, forceReasoning: true, reasoningEffort: "low", reasoningSummary: "auto", include: ["reasoning.encrypted_content"] } },
      });
      const text = await result.text;
      return { ok: true as const, text: text || (done.length ? "تم." : ""), actions: done };
    } catch (e) {
      console.error("assistant error", e);
      const status = (e as { statusCode?: number })?.statusCode;
      return { ok: false as const, message: status === 402 || status === 403 ? "انتهى رصيد الذكاء الاصطناعي المتاح حالياً" : status === 429 ? "طلبات كثيرة، حاول بعد قليل" : "تعذر الوصول إلى المساعد حالياً", actions: done };
    }
  });
