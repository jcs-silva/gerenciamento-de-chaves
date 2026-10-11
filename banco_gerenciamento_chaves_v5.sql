-- ============================================================
-- BANCO DE DADOS: Sistema de Gerenciamento de Chaves
-- MySQL 8.0+
--
-- Níveis de acesso:
--   1) Gerente Geral
--   2) Porteiro
--
-- REGRAS:
--   Gerente Geral:
--     - cadastra, edita e desativa porteiros;
--     - também pode executar as funções do Porteiro.
--
--   Porteiro:
--     - acessa Dashboard;
--     - consulta chaves;
--     - registra retirada e devolução;
--     - registra observações do dia;
--     - consulta histórico;
--     - consulta/gera relatórios.
--
-- Observação importante:
--   O campo Cargo guarda o nível de acesso. O BACKEND deve
--   controlar as permissões de cada tela/operação.
--
-- LOGIN:
--   - O usuário entra com o CPF e a senha.
--   - A senha inicial é formada pelos 4 primeiros dígitos do CPF.
--   - O backend deve transformar esses 4 dígitos em hash e armazená-los
--     em Senha_hash; o banco não deve guardar a senha em texto puro.
-- ============================================================

CREATE DATABASE IF NOT EXISTS gerenciamento_chaves
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE gerenciamento_chaves;

-- ============================================================
-- 1. USUARIOS
-- Cadastro dos usuários do sistema.
-- O Gerente Geral cadastra os Porteiros.
-- CPF é usado como identificador de login e deve conter 11 dígitos.
-- ============================================================
CREATE TABLE IF NOT EXISTS usuarios (
    ID_user INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    Nome VARCHAR(100) NOT NULL,
    Cargo ENUM('Gerente Geral', 'Porteiro') NOT NULL,
    CPF CHAR(11) NOT NULL UNIQUE,
    `E-mail` VARCHAR(150) NOT NULL UNIQUE,
    Senha_hash VARCHAR(255) NOT NULL,
    Ativo BOOLEAN NOT NULL DEFAULT TRUE,
    criado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- ============================================================
-- 2. SALAS
-- Uma sala pode possuir várias chaves.
-- ============================================================
CREATE TABLE IF NOT EXISTS salas (
    ID_sala INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `Número` VARCHAR(20) NOT NULL,
    Bloco VARCHAR(50) NOT NULL,
    CONSTRAINT uq_sala_numero_bloco UNIQUE (`Número`, Bloco)
);

-- ============================================================
-- 3. CHAVES
-- ID_sala liga a chave à sala.
-- responsavel guarda o ID_user atualmente responsável pela chave.
-- ============================================================
CREATE TABLE IF NOT EXISTS chaves (
    ID_chaves INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    ID_sala INT UNSIGNED NOT NULL,
    `Número da chave` VARCHAR(30) NOT NULL UNIQUE,
    status ENUM('Disponivel', 'Emprestada', 'Atrasada') NOT NULL DEFAULT 'Disponivel',
    responsavel INT UNSIGNED NULL,

    CONSTRAINT fk_chaves_sala
        FOREIGN KEY (ID_sala)
        REFERENCES salas(ID_sala)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

    CONSTRAINT fk_chaves_responsavel
        FOREIGN KEY (responsavel)
        REFERENCES usuarios(ID_user)
        ON UPDATE CASCADE
        ON DELETE SET NULL
);

-- ============================================================
-- 4. MOVIMENTACOES
-- Histórico das retiradas e devoluções.
-- Cada retirada cria uma linha.
-- A devolução preenche data_hora_devolucao na mesma linha.
--
-- ID_user = usuário responsável pela chave.
-- ID_porteiro = porteiro/gerente que registrou a movimentação.
-- Esses dois campos são diferentes para manter o histórico correto.
-- ============================================================
CREATE TABLE IF NOT EXISTS movimentacoes (
    ID_movimentacao INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    ID_chaves INT UNSIGNED NOT NULL,
    ID_user INT UNSIGNED NOT NULL,
    ID_porteiro INT UNSIGNED NOT NULL,
    data_hora_retirada DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    data_hora_prevista_devolucao DATETIME NOT NULL,
    data_hora_devolucao DATETIME NULL,
    status ENUM('Emprestada', 'Atrasada', 'Devolvida') NOT NULL DEFAULT 'Emprestada',
    observacao VARCHAR(500) NULL,
    criado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT fk_mov_chave
        FOREIGN KEY (ID_chaves)
        REFERENCES chaves(ID_chaves)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

    CONSTRAINT fk_mov_usuario
        FOREIGN KEY (ID_user)
        REFERENCES usuarios(ID_user)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

    CONSTRAINT fk_mov_porteiro
        FOREIGN KEY (ID_porteiro)
        REFERENCES usuarios(ID_user)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

    CONSTRAINT chk_datas_movimentacao
        CHECK (
            data_hora_devolucao IS NULL
            OR data_hora_devolucao >= data_hora_retirada
        )
);

-- ============================================================
-- 5. OBSERVACOES_DO_DIA
-- Registro das ocorrências/observações feitas pelo porteiro durante
-- o dia/turno. Cada registro fica armazenado e forma o histórico.
--
-- Pode haver várias ocorrências no mesmo dia para o mesmo porteiro.
-- ============================================================
CREATE TABLE IF NOT EXISTS observacoes_do_dia (
    ID_observacao INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    ID_porteiro INT UNSIGNED NOT NULL,
    Data_dia DATE NOT NULL,
    Data_hora DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    Observacao TEXT NOT NULL,
    criado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT fk_observacao_porteiro
        FOREIGN KEY (ID_porteiro)
        REFERENCES usuarios(ID_user)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
);

-- ============================================================
-- INDICES
-- ============================================================
CREATE INDEX idx_usuarios_cargo_ativo ON usuarios(Cargo, Ativo);
CREATE INDEX idx_usuarios_cpf ON usuarios(CPF);
CREATE INDEX idx_chaves_status ON chaves(status);
CREATE INDEX idx_chaves_responsavel ON chaves(responsavel);
CREATE INDEX idx_chaves_sala ON chaves(ID_sala);
CREATE INDEX idx_mov_chave ON movimentacoes(ID_chaves);
CREATE INDEX idx_mov_usuario ON movimentacoes(ID_user);
CREATE INDEX idx_mov_porteiro ON movimentacoes(ID_porteiro);
CREATE INDEX idx_mov_status ON movimentacoes(status);
CREATE INDEX idx_mov_retirada ON movimentacoes(data_hora_retirada);
CREATE INDEX idx_mov_prevista ON movimentacoes(data_hora_prevista_devolucao);
CREATE INDEX idx_mov_devolucao ON movimentacoes(data_hora_devolucao);
CREATE INDEX idx_obs_porteiro_data ON observacoes_do_dia(ID_porteiro, Data_dia);
CREATE INDEX idx_obs_data_hora ON observacoes_do_dia(Data_hora);

-- ============================================================
-- TRIGGER 1: VALIDAR RETIRADA
-- Impede retirar uma chave que já esteja em aberto.
-- ============================================================
DELIMITER $$

CREATE TRIGGER trg_validar_nova_retirada
BEFORE INSERT ON movimentacoes
FOR EACH ROW
BEGIN
    IF EXISTS (
        SELECT 1
        FROM movimentacoes m
        WHERE m.ID_chaves = NEW.ID_chaves
          AND m.data_hora_devolucao IS NULL
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'A chave ja possui uma movimentacao em aberto.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM chaves c
        WHERE c.ID_chaves = NEW.ID_chaves
          AND c.status IN ('Emprestada', 'Atrasada')
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'A chave nao esta disponivel para retirada.';
    END IF;
END$$

-- ============================================================
-- TRIGGER 2: RETIRADA
-- Atualiza a chave para Emprestada/Atrasada e define responsável atual.
-- ============================================================
CREATE TRIGGER trg_movimentacao_retirada
AFTER INSERT ON movimentacoes
FOR EACH ROW
BEGIN
    IF NEW.data_hora_devolucao IS NULL THEN
        UPDATE chaves
        SET status = NEW.status,
            responsavel = NEW.ID_user
        WHERE ID_chaves = NEW.ID_chaves;
    END IF;
END$$

-- ============================================================
-- TRIGGER 3: DEVOLUÇÃO
-- Libera a chave e remove o responsável atual.
-- ============================================================
CREATE TRIGGER trg_movimentacao_devolucao
AFTER UPDATE ON movimentacoes
FOR EACH ROW
BEGIN
    IF OLD.data_hora_devolucao IS NULL
       AND NEW.data_hora_devolucao IS NOT NULL THEN
        UPDATE chaves
        SET status = 'Disponivel',
            responsavel = NULL
        WHERE ID_chaves = NEW.ID_chaves;
    END IF;
END$$

DELIMITER ;

-- ============================================================
-- VIEW: LISTA DE CHAVES
-- ============================================================
CREATE OR REPLACE VIEW vw_lista_chaves AS
SELECT
    c.ID_chaves,
    c.`Número da chave`,
    c.status,
    s.ID_sala,
    s.`Número` AS numero_sala,
    s.Bloco,
    u.ID_user AS ID_responsavel,
    u.Nome AS responsavel
FROM chaves c
INNER JOIN salas s ON s.ID_sala = c.ID_sala
LEFT JOIN usuarios u ON u.ID_user = c.responsavel;

-- ============================================================
-- VIEW: HISTORICO DE MOVIMENTAÇÕES
-- ============================================================
CREATE OR REPLACE VIEW vw_historico_movimentacoes AS
SELECT
    m.ID_movimentacao,
    c.ID_chaves,
    c.`Número da chave`,
    s.ID_sala,
    s.`Número` AS numero_sala,
    s.Bloco,
    u.ID_user,
    u.Nome AS responsavel,
    u.Cargo AS cargo_responsavel,
    p.ID_user AS ID_porteiro,
    p.Nome AS porteiro_registro,
    p.Cargo AS cargo_porteiro,
    m.data_hora_retirada,
    m.data_hora_prevista_devolucao,
    m.data_hora_devolucao,
    m.status,
    m.observacao
FROM movimentacoes m
INNER JOIN chaves c ON c.ID_chaves = m.ID_chaves
INNER JOIN salas s ON s.ID_sala = c.ID_sala
INNER JOIN usuarios u ON u.ID_user = m.ID_user
INNER JOIN usuarios p ON p.ID_user = m.ID_porteiro;

-- ============================================================
-- VIEW: HISTORICO DE OBSERVAÇÕES DO DIA
-- ============================================================
CREATE OR REPLACE VIEW vw_historico_observacoes AS
SELECT
    o.ID_observacao,
    o.Data_dia,
    o.Data_hora,
    o.Observacao,
    u.ID_user AS ID_porteiro,
    u.Nome AS porteiro,
    u.Cargo
FROM observacoes_do_dia o
INNER JOIN usuarios u ON u.ID_user = o.ID_porteiro;

-- ============================================================
-- VIEW: DASHBOARD DE CHAVES
-- ============================================================
CREATE OR REPLACE VIEW vw_dashboard_chaves AS
SELECT
    c.ID_chaves,
    c.`Número da chave`,
    s.`Número` AS numero_sala,
    s.Bloco,
    CASE
        WHEN c.status IN ('Emprestada', 'Atrasada')
             AND m.data_hora_devolucao IS NULL
             AND m.data_hora_prevista_devolucao < NOW()
            THEN 'Atrasada'
        ELSE c.status
    END AS status_atual,
    u.Nome AS responsavel,
    m.data_hora_retirada,
    m.data_hora_prevista_devolucao
FROM chaves c
INNER JOIN salas s ON s.ID_sala = c.ID_sala
LEFT JOIN usuarios u ON u.ID_user = c.responsavel
LEFT JOIN movimentacoes m
    ON m.ID_chaves = c.ID_chaves
   AND m.data_hora_devolucao IS NULL;

-- ============================================================
-- CONSULTAS ÚTEIS
-- ============================================================

-- Quantidade de chaves disponíveis:
-- SELECT COUNT(*) FROM vw_dashboard_chaves WHERE status_atual = 'Disponivel';

-- Quantidade de chaves emprestadas:
-- SELECT COUNT(*) FROM vw_dashboard_chaves WHERE status_atual = 'Emprestada';

-- Quantidade de chaves atrasadas:
-- SELECT COUNT(*) FROM vw_dashboard_chaves WHERE status_atual = 'Atrasada';

-- Chaves que precisam ser devolvidas hoje:
-- SELECT * FROM vw_dashboard_chaves
-- WHERE DATE(data_hora_prevista_devolucao) = CURDATE()
--   AND responsavel IS NOT NULL;

-- Últimas movimentações:
-- SELECT * FROM vw_historico_movimentacoes
-- ORDER BY data_hora_retirada DESC LIMIT 10;

-- Histórico de observações do dia:
-- SELECT * FROM vw_historico_observacoes
-- ORDER BY Data_hora DESC;

-- Observações de um porteiro em uma data:
-- SELECT * FROM vw_historico_observacoes
-- WHERE ID_porteiro = 1 AND Data_dia = CURDATE()
-- ORDER BY Data_hora DESC;

-- Histórico de um dia inteiro:
-- SELECT * FROM vw_historico_observacoes
-- WHERE Data_dia = '2026-09-30'
-- ORDER BY Data_hora ASC;

-- Relatório por período:
-- SELECT * FROM vw_historico_movimentacoes
-- WHERE data_hora_retirada BETWEEN '2026-09-01 00:00:00'
--                              AND '2026-09-30 23:59:59'
-- ORDER BY data_hora_retirada DESC;

-- ============================================================
-- EXEMPLO DE CADASTRO
-- A senha inicial de cada usuário será os 4 primeiros dígitos do CPF.
-- Exemplo: CPF 12345678901 -> senha inicial 1234.
-- O backend deve armazenar somente o HASH de '1234' em Senha_hash.
--
-- INSERT INTO usuarios (Nome, Cargo, CPF, `E-mail`, Senha_hash)
-- VALUES ('Nome do Gerente', 'Gerente Geral', '12345678901',
--         'gerente@exemplo.com', 'HASH_DA_SENHA_1234');
--
-- INSERT INTO usuarios (Nome, Cargo, CPF, `E-mail`, Senha_hash)
-- VALUES ('Nome do Porteiro', 'Porteiro', '98765432100',
--         'porteiro@exemplo.com', 'HASH_DA_SENHA_9876');
--
-- LOGIN:
-- SELECT ID_user, Nome, Cargo, Senha_hash, Ativo
-- FROM usuarios
-- WHERE CPF = '12345678901' AND Ativo = TRUE;
--
-- Depois de encontrar o usuário, o BACKEND deve verificar a senha
-- informada (os 4 primeiros dígitos do CPF) contra Senha_hash
-- usando password_verify/bcrypt ou equivalente.
-- Nunca compare ou armazene a senha em texto puro no banco.
-- ============================================================
