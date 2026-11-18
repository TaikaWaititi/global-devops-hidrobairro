-- Executar com o usuario do schema Java no Oracle em nuvem.
-- Registros exclusivos desta execucao; nao modifica dados preexistentes.
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
SET AUTOCOMMIT OFF
SET PAGESIZE 100
SET LINESIZE 200
COLUMN nome FORMAT A32
COLUMN email FORMAT A50
COLUMN papel FORMAT A10
COLUMN zona FORMAT A10
COLUMN origem FORMAT A10
COLUMN status FORMAT A12
COLUMN mensagem FORMAT A40
VARIABLE usuario_id NUMBER
VARIABLE ponto_id NUMBER
VARIABLE leitura_id NUMBER
VARIABLE alerta_id NUMBER

PROMPT CREATE - Quatro tabelas, usando IDs gerados pelo Oracle
BEGIN
    INSERT INTO usuario_hb(nome,email,senha_hash,papel,ativo,criado_em)
    VALUES ('Teste SQL DevOps', RAWTOHEX(SYS_GUID()) || '@example.test',
            'CONTA-SEM-LOGIN-EXCLUSIVA-DO-TESTE-SQL', 'CIDADAO','S',CURRENT_TIMESTAMP)
    RETURNING id INTO :usuario_id;
    INSERT INTO ponto_monitoramento_hb(nome,subprefeitura,bairro,zona,latitude,longitude,limiar_alerta_cm,ativo,criado_em)
    VALUES ('Teste SQL Campo Limpo','Campo Limpo','Campo Limpo','SUL',-23.6485,-46.7652,50,'S',CURRENT_TIMESTAMP)
    RETURNING id INTO :ponto_id;
    INSERT INTO leitura_hb(ponto_id,nivel_cm,coletado_em,origem)
    VALUES (:ponto_id,60,CURRENT_TIMESTAMP,'SIMULADO') RETURNING id INTO :leitura_id;
    INSERT INTO alerta_hb(ponto_id,leitura_id,nivel_cm,severidade,mensagem,status,criado_em)
    VALUES (:ponto_id,:leitura_id,60,'ATENCAO','Teste SQL de alerta','ATIVO',CURRENT_TIMESTAMP)
    RETURNING id INTO :alerta_id;
END;
/
PROMPT READ - Prova diretamente por SELECT, sem usar GET
SELECT id,nome,email,papel,ativo FROM usuario_hb WHERE id=:usuario_id;
SELECT id,nome,zona,limiar_alerta_cm FROM ponto_monitoramento_hb WHERE id=:ponto_id;
SELECT id,ponto_id,nivel_cm,origem FROM leitura_hb WHERE id=:leitura_id;
SELECT id,ponto_id,leitura_id,nivel_cm,status FROM alerta_hb WHERE id=:alerta_id;

PROMPT UPDATE - Alteracao dos quatro registros de teste
UPDATE usuario_hb SET nome='Teste SQL atualizado' WHERE id=:usuario_id;
UPDATE ponto_monitoramento_hb SET nome='Teste SQL ponto atualizado' WHERE id=:ponto_id;
UPDATE leitura_hb SET nivel_cm=70 WHERE id=:leitura_id;
UPDATE alerta_hb SET nivel_cm=70,mensagem='Teste SQL atualizado' WHERE id=:alerta_id;
SELECT id,nome FROM usuario_hb WHERE id=:usuario_id;
SELECT id,nome FROM ponto_monitoramento_hb WHERE id=:ponto_id;
SELECT id,nivel_cm FROM leitura_hb WHERE id=:leitura_id;
SELECT id,nivel_cm,mensagem FROM alerta_hb WHERE id=:alerta_id;

PROMPT DELETE - Ordem respeita as chaves estrangeiras
DELETE FROM alerta_hb WHERE id=:alerta_id;
DELETE FROM leitura_hb WHERE id=:leitura_id;
DELETE FROM ponto_monitoramento_hb WHERE id=:ponto_id;
DELETE FROM usuario_hb WHERE id=:usuario_id;
SELECT 'USUARIO_HB' tabela,COUNT(*) restantes FROM usuario_hb WHERE id=:usuario_id
UNION ALL SELECT 'PONTO_MONITORAMENTO_HB',COUNT(*) FROM ponto_monitoramento_hb WHERE id=:ponto_id
UNION ALL SELECT 'LEITURA_HB',COUNT(*) FROM leitura_hb WHERE id=:leitura_id
UNION ALL SELECT 'ALERTA_HB',COUNT(*) FROM alerta_hb WHERE id=:alerta_id;
ROLLBACK;
PROMPT Teste finalizado sem persistir registros de demonstracao.
EXIT SUCCESS
