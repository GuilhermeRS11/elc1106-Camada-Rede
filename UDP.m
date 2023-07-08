clc; clear all; close all;

% ---------------------------------------------------------
% Parâmetro modificável da rede. Efeito no Packet Loss Rate
n = 20; % numero de nos da rede
% ---------------------------------------------------------

% Inicia o gerador de numeros aleatorios
rand("state", 0);

% Parametros principais
tempo_simulacao = 100; % tempo de simulacao

% Lista de eventos executados
global Log_eventos = [];
global eventos_executados = 0;

global msg = {"hello"};
global rede = ~eye(n); % matriz de conectividade da rede
global nos = [];

% Definir a estrutura do cabeçalho do UDP
global udp_header_size = 8; % Tamanho do cabeçalho UDP em bytes

global total_packets_received = 0;
global total_packets_sent = 0;

% Função para calcular o checksum do cabeçalho UDP
function checksum = calculateChecksum(header)
    % Implemente aqui o cálculo do checksum (opcional para a simulação)
    checksum = 0;
end

function Log_eventos = exec_simulador(Lista_eventos, Log_eventos, tempo_final)
    global eventos_executados;

    % Simulacao discreta por eventos
    while 1
        [min_instante, min_indice] = min([Lista_eventos(:).instante]);
        if isempty(min_instante)
            break;
        end
        if min_instante > tempo_final
            break;
        end
        ev = Lista_eventos(min_indice);
        Lista_eventos(min_indice) = []; % Remove o evento da lista, pois sera executado.
        tempo_atual = min_instante;
        Log_eventos = [Log_eventos; ev];

        Novos_eventos = executa_evento(ev, tempo_atual); % Retorna os novos eventos apos executar o ultimo evento
        eventos_executados += 1;

        if ~isempty(Novos_eventos) % adiciona novos eventos na lista
            Lista_eventos = [Lista_eventos; Novos_eventos];
        end
    end
end

function [NovosEventos] = executa_evento(evento, tempo_atual)
    global msg, global rede, global nos, global udp_header_size;
    global total_packets_received, global total_packets_sent;

    NovosEventos = [];

    % Configuração
    dist = 100; % 100m
    tempo_prop = dist / 3e8; %tempo de propagacao = distancia/velocidade do sinal
    taxa_dados = 1e5; % 100kbps

    [t, tipo_evento, id, pct] = evento_desmonta(evento); % retorna os campos do 'evento'
    disp(['EV: ' tipo_evento ' @t=' num2str(t) ' id=' num2str(id)]);

    switch tipo_evento
        case 'N_cfg' % configura nos, inicia variaveis de estado, etc.
            nos(id).Tx = 'desocupado';
            nos(id).Rx = 'desocupado';
            nos(id).ocupado_ate = 0;
            nos(id).stat = struct("tx", 0, "rx", 0, "rxok", 0, "col", 0);

            % adiciona uma trasmissao na fila
            % pacote contem origem (src), destino (dst), tamanho (tam) e os dados
            pct = struct('src', id, 'dst', 0, 'tam', 20, 'dados', msg);

            % Add IP header fields
            ip_header = struct('source_ip', '192.168.0.1', 'destination_ip', '192.168.0.2');
            pct.ip_header = ip_header;

            % Add UDP header fields
            udp_header = struct('source_port', 5000, 'destination_port', 6000, 'length', udp_header_size + pct.tam, 'checksum', 0);
            pct.udp_header = udp_header;

            e = evento_monta(tempo_atual + rand(1), 'T_ini', id, pct);
            NovosEventos = [NovosEventos; e];

        case 'T_ini' %inicio de transmissao
            if strcmp(nos(id).Tx, 'ocupado') % transmissor ocupado?
                tempo_entre_quadros = 0.2 * 8 * pct.tam / taxa_dados; %20\% do tempo de transmissao
                e = evento_monta(nos(id).ocupado_ate + tempo_entre_quadros, 'T_ini', id, pct);
                NovosEventos = [NovosEventos; e];
            else
                if pct.dst == 0 %pacote de broadcast
                    for nid = find(rede(id, :) > 0) % envia uma copia do pacote para cada vizinho
                        disp(['INI T de ' num2str(id) ' para ' num2str(nid)]);
                        e = evento_monta((tempo_atual + tempo_prop), 'R_ini', nid, pct);
                        NovosEventos = [NovosEventos; e];
                    end
                else % envia um pacote para o vizinho, se conectado
                    if find(rede(id, :) == pct.dst)
                        disp(['INI T de ' num2str(id) ' para ' num2str(pct.dst)]);
                        e = evento_monta((tempo_atual + tempo_prop), 'R_ini', pct.dst, pct);
                        NovosEventos = [NovosEventos; e];
                    end
                end
                tempo_transmissao = 8 * pct.tam / taxa_dados;
                e = evento_monta((tempo_atual + tempo_transmissao), 'T_fim', id, pct);
                NovosEventos = [NovosEventos; e];
                nos(id).Tx = 'ocupado';
                nos(id).ocupado_ate = tempo_atual + tempo_transmissao;
            end
        case 'T_fim' %fim de transmissao
            nos(id).stat.tx += 1;
            nos(id).Tx = 'desocupado';
            nos(id).ocupado_ate = 0;
        case 'R_ini' %inicio de recepcao

            %if ~isempty(pct); disp(pct); end;
            if strcmp(nos(id).Rx, 'ocupado') || strcmp(nos(id).Rx, 'colisao')
                nos(id).Rx = 'colisao';
                nos(id).stat.rx += 1;
                disp('--- Pacote perdido ---');
            else
                nos(id).Rx = 'ocupado';
                nos(id).stat.rx = 1;
            end
            e = evento_monta((tempo_atual + 8 * pct.tam / taxa_dados), 'R_fim', id, pct);
            NovosEventos = [NovosEventos; e];
            total_packets_sent += 1;

        case 'R_fim' %fim de recepcao
            nos(id).stat.rx -= 1;
            if strcmp(nos(id).Rx, 'ocupado')
                disp("");
                disp(['FIM R de ' num2str(pct.src) ' para ' num2str(pct.dst)']);

                disp('--- Pacote recebido ---');
                total_packets_received += 1;

                 % Print packet details
                disp(['Origem: ' num2str(pct.src)]);
                disp(['Destino: ' num2str(pct.dst)]);
                disp(['Tamanho: ' num2str(pct.tam)]);
                disp(['Dados: ' num2str(pct.dados)]);
                disp('IP Header: ');
                disp(pct.ip_header);
                disp('UDP Header: ');
                disp(pct.udp_header);
            elseif strcmp(nos(id).Rx, 'colisao')
                if (nos(id).stat.rx == 0)
                    nos(id).Rx = 'desocupado';
                    nos(id).stat.col += 1;
                end
            else
                disp("ERRO: Estado Rx errado.");
            end
        case 'S_fim' %fim de simulacao
            disp('Simulacao encerrada!');
        otherwise
            disp(['exec_evento: Evento desconhecido: ' tipo_evento]);
    end

end

function [t, tipo, id, pct] = evento_desmonta(e)
    t = e.instante;
    tipo = e.tipo;
    id = e.id;
    pct = e.pct;
end

function e = evento_monta(t, tipo, id, pct)
    if nargin < 4, pct = []; end
    e = struct('instante', t, 'tipo', tipo, 'id', id);
    e.pct = pct;
end

function Lista_eventos = config_sim(n, tempo_simulacao)
    Lista_eventos = [];
    for k = 1:n
        e = evento_monta(0, 'N_cfg', k);
        Lista_eventos = [Lista_eventos; e];
    end

    ev_fim = evento_monta(tempo_simulacao, 'S_fim', 0);
    Lista_eventos = [Lista_eventos; ev_fim];
end

% Configura a simulacao
tempo_inicial = clock();
Lista_eventos = config_sim(n, tempo_simulacao);

% Executa a simulacao
Log_eventos = exec_simulador(Lista_eventos, Log_eventos, tempo_simulacao);
print_struct_array_contents(1);
% Log_eventos(:).instante
% Log_eventos(:).tipo
disp(['---Total de eventos=' num2str(eventos_executados)]);
disp(sprintf('---Tempo da simulacao=%g segundos', etime(clock, tempo_inicial)));

% Faz o calculo da % de pacotes perdidos
packet_loss_rate = 1 - (total_packets_received / total_packets_sent);
disp(['Packet Loss Rate: ' num2str(packet_loss_rate)]);

