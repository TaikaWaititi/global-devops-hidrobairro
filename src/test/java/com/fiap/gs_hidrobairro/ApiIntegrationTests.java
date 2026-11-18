package com.fiap.gs_hidrobairro;

import com.fiap.gs_hidrobairro.model.Usuario;
import com.fiap.gs_hidrobairro.model.enums.PapelUsuario;
import com.fiap.gs_hidrobairro.repository.UsuarioRepository;
import com.fiap.gs_hidrobairro.publisher.AlertaEventPublisher;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import java.time.LocalDateTime;
import java.util.UUID;
import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class ApiIntegrationTests {
    @Autowired MockMvc mvc;
    @Autowired JdbcTemplate jdbc;
    @Autowired UsuarioRepository usuarios;
    @Autowired PasswordEncoder encoder;
    @MockitoBean AlertaEventPublisher publisher;
    String gestorToken;
    Long gestorId;

    @BeforeEach
    void criarGestor() throws Exception {
        Usuario gestor = new Usuario();
        gestor.setNome("Gestor Teste");
        gestor.setEmail(UUID.randomUUID()+"@example.test");
        gestor.setSenhaHash(encoder.encode("senha-teste-123"));
        gestor.setPapel(PapelUsuario.GESTOR);
        gestor.setCriadoEm(LocalDateTime.now());
        usuarios.saveAndFlush(gestor);
        gestorId = gestor.getId();
        gestorToken = login(gestor.getEmail());
    }

    String login(String email) throws Exception {
        String body = mvc.perform(post("/api/auth/login").contentType("application/json")
                .content("{\"email\":\""+email+"\",\"senha\":\"senha-teste-123\"}"))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        return tools.jackson.databind.json.JsonMapper.builder().build().readTree(body).get("token").asString();
    }

    String usuario(String email, String nome, String papel) {
        return "{\"nome\":\""+nome+"\",\"email\":\""+email+"\",\"senha\":\"senha-teste-123\",\"papel\":\""+papel+"\"}";
    }

    @Test void crudUsuarioComPersistenciaSql() throws Exception {
        String email = UUID.randomUUID()+"@example.test";
        mvc.perform(post("/api/usuarios").contentType("application/json").content(usuario(email,"Cidadao Teste","CIDADAO")))
                .andExpect(status().isCreated());
        Long id = jdbc.queryForObject("SELECT id FROM usuario_hb WHERE email=?",Long.class,email);
        String token=login(email);
        mvc.perform(get("/api/usuarios/"+id).header("Authorization","Bearer "+token)).andExpect(status().isOk());
        mvc.perform(put("/api/usuarios/"+id).header("Authorization","Bearer "+token)
                .contentType("application/json").content(usuario(email,"Nome atualizado","CIDADAO"))).andExpect(status().isOk());
        assertEquals("Nome atualizado",jdbc.queryForObject("SELECT nome FROM usuario_hb WHERE id=?",String.class,id));
        mvc.perform(delete("/api/usuarios/"+id).header("Authorization","Bearer "+gestorToken)).andExpect(status().isNoContent());
        assertEquals(0,jdbc.queryForObject("SELECT COUNT(*) FROM usuario_hb WHERE id=?",Integer.class,id));
        mvc.perform(get("/api/usuarios").header("Authorization","Bearer "+token)).andExpect(status().isUnauthorized());
    }

    String ponto(String nome) {
        return "{\"nome\":\""+nome+"\",\"subprefeitura\":\"Campo Limpo\",\"bairro\":\"Campo Limpo\",\"zona\":\"SUL\",\"latitude\":-23.6485,\"longitude\":-46.7652,\"limiarAlertaCm\":50}";
    }

    @Test void crudPontoComPersistenciaSql() throws Exception {
        String nome="Ponto "+UUID.randomUUID();
        mvc.perform(post("/api/pontos-monitoramento").header("Authorization","Bearer "+gestorToken)
                .contentType("application/json").content(ponto(nome))).andExpect(status().isCreated());
        Long id=jdbc.queryForObject("SELECT id FROM ponto_monitoramento_hb WHERE nome=?",Long.class,nome);
        mvc.perform(get("/api/pontos-monitoramento/"+id).header("Authorization","Bearer "+gestorToken)).andExpect(status().isOk());
        mvc.perform(put("/api/pontos-monitoramento/"+id).header("Authorization","Bearer "+gestorToken)
                .contentType("application/json").content(ponto("Ponto atualizado"))).andExpect(status().isOk());
        assertEquals("Ponto atualizado",jdbc.queryForObject("SELECT nome FROM ponto_monitoramento_hb WHERE id=?",String.class,id));
        mvc.perform(delete("/api/pontos-monitoramento/"+id).header("Authorization","Bearer "+gestorToken)).andExpect(status().isNoContent());
        assertEquals(0,jdbc.queryForObject("SELECT COUNT(*) FROM ponto_monitoramento_hb WHERE id=?",Integer.class,id));
        mvc.perform(get("/api/pontos-monitoramento/"+id).header("Authorization","Bearer "+gestorToken)).andExpect(status().isNotFound());
    }

    @Test void pontoComHistoricoNaoPodeSerExcluido() throws Exception {
        String nome="Historico "+UUID.randomUUID();
        mvc.perform(post("/api/pontos-monitoramento").header("Authorization","Bearer "+gestorToken)
                .contentType("application/json").content(ponto(nome))).andExpect(status().isCreated());
        Long id=jdbc.queryForObject("SELECT id FROM ponto_monitoramento_hb WHERE nome=?",Long.class,nome);
        jdbc.update("INSERT INTO leitura_hb(ponto_id,nivel_cm,coletado_em,origem) VALUES (?,10,CURRENT_TIMESTAMP,'SIMULADO')",id);
        mvc.perform(delete("/api/pontos-monitoramento/"+id).header("Authorization","Bearer "+gestorToken)).andExpect(status().isConflict());
        assertEquals(1,jdbc.queryForObject("SELECT COUNT(*) FROM ponto_monitoramento_hb WHERE id=?",Integer.class,id));
    }

    @Test void cadastroPublicoNaoPodeCriarGestor() throws Exception {
        String email=UUID.randomUUID()+"@example.test";
        mvc.perform(post("/api/usuarios").contentType("application/json").content(usuario(email,"Gestor indevido","GESTOR")))
                .andExpect(status().isForbidden());
        assertFalse(usuarios.existsByEmail(email));
    }

    @Test void emailDuplicadoRetorna409() throws Exception {
        String email=UUID.randomUUID()+"@example.test";
        String json=usuario(email,"Duplicado Teste","CIDADAO");
        mvc.perform(post("/api/usuarios").contentType("application/json").content(json)).andExpect(status().isCreated());
        mvc.perform(post("/api/usuarios").contentType("application/json").content(json)).andExpect(status().isConflict());
    }

    @Test void cidadaoNaoPodeExcluirPonto() throws Exception {
        String email=UUID.randomUUID()+"@example.test";
        mvc.perform(post("/api/usuarios").contentType("application/json").content(usuario(email,"Sem Permissao","CIDADAO"))).andExpect(status().isCreated());
        mvc.perform(delete("/api/pontos-monitoramento/999999").header("Authorization","Bearer "+login(email))).andExpect(status().isForbidden());
    }

    @Test void usuarioDesativadoNaoPodeReutilizarJwt() throws Exception {
        String email=UUID.randomUUID()+"@example.test";
        mvc.perform(post("/api/usuarios").contentType("application/json").content(usuario(email,"Desativado Teste","CIDADAO"))).andExpect(status().isCreated());
        String token=login(email);
        jdbc.update("UPDATE usuario_hb SET ativo='N' WHERE email=?",email);
        mvc.perform(get("/api/pontos-monitoramento").header("Authorization","Bearer "+token)).andExpect(status().isUnauthorized());
    }

    @Test void gestorNaoPodeExcluirPropriaConta() throws Exception {
        mvc.perform(delete("/api/usuarios/"+gestorId).header("Authorization","Bearer "+gestorToken)).andExpect(status().isForbidden());
    }

    @Test void tokenInvalidoRetorna401() throws Exception {
        mvc.perform(get("/api/usuarios").header("Authorization","Bearer token-invalido")).andExpect(status().isUnauthorized());
    }

    @Test void semAutenticacaoRetorna401() throws Exception {
        mvc.perform(get("/api/pontos-monitoramento")).andExpect(status().isUnauthorized());
    }

    @Test void rotaPublicaInexistenteRetorna404() throws Exception {
        mvc.perform(get("/")).andExpect(status().isNotFound());
    }

    @Test void jsonInvalidoRetorna400() throws Exception {
        mvc.perform(post("/api/usuarios").contentType("application/json").content("{" )).andExpect(status().isBadRequest());
    }

    @Test void dadosInvalidosRetornam400() throws Exception {
        mvc.perform(post("/api/usuarios").contentType("application/json").content(usuario("email-invalido","X","CIDADAO"))).andExpect(status().isBadRequest());
    }
}
