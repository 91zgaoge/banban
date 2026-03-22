-- 用户伴侣偏好设置表
CREATE TABLE companion_user_settings (
    user_id         UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    bot_id          UUID NOT NULL REFERENCES bots(id) ON DELETE CASCADE,
    companion_name  TEXT NOT NULL DEFAULT '杏儿',
    voice_enabled   BOOLEAN NOT NULL DEFAULT true,
    voice_id        TEXT NOT NULL DEFAULT 'default',
    proactive_level TEXT NOT NULL DEFAULT 'normal'
                    CHECK (proactive_level IN ('quiet', 'normal', 'active')),
    hotkey          TEXT,
    timezone        TEXT NOT NULL DEFAULT 'Asia/Shanghai',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 主动联系日志，防止频繁打扰
CREATE TABLE companion_proactive_log (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bot_id     UUID NOT NULL REFERENCES bots(id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reason     TEXT NOT NULL,
    sent_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX companion_proactive_log_lookup
    ON companion_proactive_log (bot_id, user_id, sent_at DESC);
