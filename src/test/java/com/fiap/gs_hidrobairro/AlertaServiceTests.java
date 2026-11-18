package com.fiap.gs_hidrobairro;

import com.fiap.gs_hidrobairro.event.AlertaCriadoEvent;
import com.fiap.gs_hidrobairro.model.*;
import com.fiap.gs_hidrobairro.model.enums.*;
import com.fiap.gs_hidrobairro.repository.AlertaRepository;
import com.fiap.gs_hidrobairro.service.AlertaService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.context.ApplicationEventPublisher;
import java.math.BigDecimal;
import java.util.Optional;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class AlertaServiceTests {
    AlertaRepository repository;
    ApplicationEventPublisher publisher;
    AlertaService service;
    PontoMonitoramento ponto;

    @BeforeEach void preparar() {
        repository=mock(AlertaRepository.class);
        publisher=mock(ApplicationEventPublisher.class);
        service=new AlertaService(repository,publisher);
        ponto=new PontoMonitoramento();
        ponto.setId(1L);
        ponto.setNome("Campo Limpo");
        ponto.setLimiarAlertaCm(new BigDecimal("50"));
        when(repository.findByPontoIdAndStatus(1L,StatusAlerta.ATIVO)).thenReturn(Optional.empty());
        when(repository.save(any(Alerta.class))).thenAnswer(invocation -> {
            Alerta alerta=invocation.getArgument(0);
            alerta.setId(10L);
            return alerta;
        });
    }

    Leitura leitura(String nivel) {
        Leitura leitura=new Leitura();
        leitura.setPonto(ponto);
        leitura.setNivelCm(new BigDecimal(nivel));
        return leitura;
    }

    @Test void abaixoDoLimiarNaoGeraAlerta() {
        service.avaliarLeitura(leitura("49.99"));
        verify(repository,never()).save(any());
        verifyNoInteractions(publisher);
    }

    @Test void noLimiarGeraAtencaoEEvento() {
        service.avaliarLeitura(leitura("50"));
        ArgumentCaptor<Alerta> captor=ArgumentCaptor.forClass(Alerta.class);
        verify(repository).save(captor.capture());
        assertEquals(SeveridadeAlerta.ATENCAO,captor.getValue().getSeveridade());
        verify(publisher).publishEvent(any(AlertaCriadoEvent.class));
    }

    @Test void umaVezEMeiaOLimiarGeraCritico() {
        service.avaliarLeitura(leitura("75"));
        ArgumentCaptor<Alerta> captor=ArgumentCaptor.forClass(Alerta.class);
        verify(repository).save(captor.capture());
        assertEquals(SeveridadeAlerta.CRITICO,captor.getValue().getSeveridade());
    }

    @Test void alertaExistenteEAtualizadoSemEventoDuplicado() {
        Alerta existente=new Alerta();
        existente.setId(10L);
        when(repository.findByPontoIdAndStatus(1L,StatusAlerta.ATIVO)).thenReturn(Optional.of(existente));
        service.avaliarLeitura(leitura("80"));
        verify(repository).save(existente);
        assertEquals(SeveridadeAlerta.CRITICO,existente.getSeveridade());
        verifyNoInteractions(publisher);
    }

    @Test void quedaDoNivelEncerraAlertaAtivo() {
        Alerta existente=new Alerta();
        when(repository.findByPontoIdAndStatus(1L,StatusAlerta.ATIVO)).thenReturn(Optional.of(existente));
        service.avaliarLeitura(leitura("49"));
        assertEquals(StatusAlerta.ENCERRADO,existente.getStatus());
        assertNotNull(existente.getEncerradoEm());
        verifyNoInteractions(publisher);
    }
}
