package com.fiap.gs_hidrobairro.config;

import com.fiap.gs_hidrobairro.model.Usuario;
import com.fiap.gs_hidrobairro.model.enums.PapelUsuario;
import com.fiap.gs_hidrobairro.repository.UsuarioRepository;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;
import java.time.LocalDateTime;

@Component
@ConditionalOnProperty(name = "hidrobairro.bootstrap.enabled", havingValue = "true")
public class GestorBootstrap implements ApplicationRunner {
    private final UsuarioRepository usuarios;
    private final PasswordEncoder encoder;
    private final String email;
    private final String senha;

    public GestorBootstrap(UsuarioRepository usuarios, PasswordEncoder encoder,
            @Value("${BOOTSTRAP_GESTOR_EMAIL}") String email,
            @Value("${BOOTSTRAP_GESTOR_PASSWORD}") String senha) {
        this.usuarios = usuarios;
        this.encoder = encoder;
        this.email = email;
        this.senha = senha;
    }

    @Override
    @Transactional
    public void run(ApplicationArguments args) {
        if (senha.length() < 12 || !email.contains("@")) {
            throw new IllegalArgumentException("Configure credenciais válidas do gestor (senha mínima de 12 caracteres)");
        }
        var existente = usuarios.findByEmail(email);
        if (existente.isPresent()) {
            if (existente.get().getPapel() != PapelUsuario.GESTOR) {
                throw new IllegalStateException("Conta de bootstrap já existe como cidadão; promoção automática recusada");
            }
            return;
        }
        Usuario usuario = new Usuario();
        usuario.setNome("Gestor HidroBairro Sul");
        usuario.setEmail(email);
        usuario.setSenhaHash(encoder.encode(senha));
        usuario.setPapel(PapelUsuario.GESTOR);
        usuario.setCriadoEm(LocalDateTime.now());
        usuarios.save(usuario);
    }
}
