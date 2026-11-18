package com.fiap.gs_hidrobairro;

import org.junit.jupiter.api.Test;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@ActiveProfiles({"test", "cloud"})
@TestPropertySource(properties = "spring.ai.google.genai.api-key=")
class ApiCloudWithoutAiTests extends ApiIntegrationTests {
    @Test void orientacaoSemProvedorRetorna503SemRespostaInventada() throws Exception {
        mvc.perform(post("/api/ia/orientacoes").header("Authorization", "Bearer " + gestorToken)
                .contentType("application/json").content("{\"pergunta\":\"Como está Campo Limpo?\"}"))
                .andExpect(status().isServiceUnavailable());
    }
}
