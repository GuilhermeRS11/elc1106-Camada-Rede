clc; clear all; close all;

% Inicia o gerador de números aleatórios
rand("state", 0);

% Parâmetros principais
tempo_simulacao = 100; % tempo de simulação

% Lista de eventos executados
global Log_eventos = [];
global eventos_executados = 0;

n = 20; % número de nós da rede
global msg = "hello";
global rede = ~eye(n); % matriz de conectividade da rede
global nos = [];

function Log_eventos = exec_simulador(Lista_eventos, Log_eventos, tempo_final)

  global eventos_executados;

  % Simulação discreta por eventos
  while 1
    [min_instante, min_indice] = min([Lista_eventos(:).instante]);
    if isempty(min_instante)
      break;
    end
    if min_instante > tempo_final
      break;
    end
    ev = Lista_eventos(min_indice);
    Lista_eventos(min_indice) = []; % Remove o evento da lista, pois será executado.
    tempo_atual = min_instante;
    Log_eventos = [Log_eventos; ev];

    Novos_eventos = executa_evento(ev, tempo_atual); % Retorna os novos eventos após executar o último evento
    eventos_executados += 1;

    if ~isempty(Novos_eventos) % Adiciona novos eventos na lista
      Lista_eventos = [Lista_eventos; Novos_eventos];
    end
  end
end

function [NovosEventos] = executa_evento(evento, tempo_atual)
  global msg, global rede, global nos;

  NovosEventos = [];

  % Configuração
  dist = 100; % 100m
  tempo_prop = dist / 3e8; % tempo de propagação = distância/velocidade do sinal

  [t, tipo_evento, id, pct] = evento_desmonta(evento); % Retorna os campos do 'evento'
  disp(['EV: ' tipo_evento ' @t=' num2str(t) ' id=' num2str(id)]);

  switch tipo_evento
    case 'N_cfg' % Configura nós, inicia variáveis de estado, etc.
      nos(id).ocupado_ate = 0;

      % Adiciona um envio na fila
      pct = struct('src', id, 'dst', 0, 'dados', msg);

      e = evento_monta(tempo_atual + rand(1), 'S_ini', id, pct);
      NovosEventos = [NovosEventos; e];

    case 'S_ini' % Início do envio
      if nos(id).ocupado_ate > tempo_atual % Verifica se o nó está ocupado
        tempo_entre_envios = 0.2; % 200ms
        e = evento_monta(nos(id).ocupado_ate + tempo_entre_envios, 'S_ini', id, pct);
        NovosEventos = [NovosEventos; e];
      else
        if pct.dst == 0 % Pacote de broadcast
          for nid = find(rede(id, :) > 0) % Envia uma cópia do pacote para cada vizinho
            disp(['INI S de ' num2str(id) ' para ' num2str(nid) ' @t=' num2str(tempo_atual)]);
            e = evento_monta(tempo_atual + tempo_prop, 'S_env', nid, pct);
            NovosEventos = [NovosEventos; e];
          end
        else % Pacote unicast
          disp(['INI S de ' num2str(id) ' para ' num2str(pct.dst) ' @t=' num2str(tempo_atual)]);
          e = evento_monta(tempo_atual + tempo_prop, 'S_env', pct.dst, pct);
          NovosEventos = [NovosEventos; e];
        end

        nos(id).ocupado_ate = tempo_atual + 0.2; % 200ms
      end

    case 'S_env' % Envio de pacote
      disp(['ENVIO de ' num2str(id) ' para ' num2str(pct.dst) ' @t=' num2str(tempo_atual)]);
      if rand(1) > 0.2 % Taxa de perda de pacotes = 20%
        e = evento_monta(tempo_atual + tempo_prop, 'S_rec', pct.dst, pct);
        NovosEventos = [NovosEventos; e];
      else
        disp('Pacote PERDIDO!');
      end

    case 'S_rec' % Recepção de pacote
      disp(['RECEP de ' num2str(id) ' de ' num2str(pct.src) ' @t=' num2str(tempo_atual)]);

      % Envio de ACK
      pct_ack = struct('src', id, 'dst', pct.src, 'dados', 'ACK');
      e = evento_monta(tempo_atual + tempo_prop, 'S_env', pct.src, pct_ack);
      NovosEventos = [NovosEventos; e];

    otherwise
      disp('Evento não tratado');
  end
end

function [ev] = evento_monta(instante, tipo, id, pct)
  ev = struct('instante', instante, 'tipo', tipo, 'id', id, 'pct', pct);
end

function [t, tipo_evento, id, pct] = evento_desmonta(evento)
  t = evento.instante;
  tipo_evento = evento.tipo;
  id = evento.id;
  pct = evento.pct;
end

% Cria os nós da rede
for i = 1:n
  nos(i).id = i;
  nos(i).ocupado_ate = 0;
end

% Configura eventos iniciais
Lista_eventos = [];
for i = 1:n
  e = evento_monta(0, 'N_cfg', i, []);
  Lista_eventos = [Lista_eventos; e];
end

% Executa a simulação
Log_eventos = exec_simulador(Lista_eventos, Log_eventos, tempo_simulacao);

% Exibe resultados
disp(['Eventos executados: ' num2str(eventos_executados)]);
disp('--- Log de Eventos ---');
for i = 1:size(Log_eventos, 1)
  [t, tipo_evento, id, pct] = evento_desmonta(Log_eventos(i, :));
  disp(['@t=' num2str(t) ' EV: ' tipo_evento ' id=' num2str(id)]);
end

