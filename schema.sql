-- Usuários: cada um com login (email) e senha.
-- A senha NUNCA é guardada em texto: só o hash gerado pelo bcrypt.
CREATE TABLE IF NOT EXISTS users (
    id            SERIAL PRIMARY KEY,
    name          VARCHAR(100) NOT NULL,
    email         VARCHAR(255) NOT NULL UNIQUE,  -- a API salva sempre em minúsculas
    password_hash VARCHAR(100) NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Tarefas: cada tarefa pertence a um usuário (relação 1:N).
CREATE TABLE IF NOT EXISTS tasks (
    id         SERIAL PRIMARY KEY,
    user_id    INTEGER      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title      VARCHAR(200) NOT NULL,
    done       BOOLEAN      NOT NULL DEFAULT false,
    done_at    TIMESTAMPTZ,                      -- hora em que a tarefa foi finalizada (NULL se não concluída)
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Toda consulta de tarefas filtra por user_id
CREATE INDEX IF NOT EXISTS idx_tasks_user_id ON tasks(user_id);
