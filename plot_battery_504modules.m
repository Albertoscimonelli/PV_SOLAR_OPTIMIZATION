%% PLOT_BATTERY_504MODULES.m
% Script per plottare i grafici della batteria per tutto l'anno
% Solo per le configurazioni con 504 moduli
%
% Genera grafici di:
%   - Consumi vs Produzione PV
%   - Stato di Carica (SOC) della batteria

clear; clc;

%% === PARAMETRI ===
BATT_EFF = 0.95;     % Efficienza carica/scarica batteria (95%)
SOC_MIN = 0.3;       % State of Charge minimo (30%)
SOC_MAX = 0.8;       % State of Charge massimo (80%)

% Path files
loadFile  = "C:\Users\scimo\OneDrive\Desktop\PoliMi\Secondo Anno\Solar and Biomass\Project\Matlab project\Consumi.csv";
pvFolder  = "C:\Users\scimo\OneDrive\Desktop\PoliMi\Secondo Anno\Solar and Biomass\Project\Matlab project\PVsyst results";

%% 1) CARICAMENTO CONSUMI ORARI
Tload = readtable(loadFile);
numCols = varfun(@isnumeric, Tload, "OutputFormat", "uniform");
idxLoad = find(numCols, 1, "first");
load_kWh = double(Tload{:, idxLoad});

%% 2) TROVA FILE CON 504 MODULI
pvFiles = dir(fullfile(pvFolder, "*.CSV"));
nFiles = numel(pvFiles);

% Filtra solo file con 504 moduli
idx504 = [];
tilts504 = [];
invPower504 = [];

for i = 1:nFiles
    tokens = regexp(pvFiles(i).name, 'HourlyRes_(\d+)_(\d+)_(\d+)', 'tokens');
    if ~isempty(tokens)
        modules = str2double(tokens{1}{1});
        tilt = str2double(tokens{1}{2});
        invPower = str2double(tokens{1}{3});
        if modules == 504
            idx504 = [idx504; i];
            tilts504 = [tilts504; tilt];
            invPower504 = [invPower504; invPower];
        end
    end
end

nCfg504 = numel(idx504);
fprintf('Trovate %d configurazioni con 504 moduli\n', nCfg504);
fprintf('Inclinazioni: %s gradi\n', mat2str(tilts504'));

%% 3) GENERA GRAFICI PER OGNI CONFIGURAZIONE 504 MODULI
% Vettore temporale per l'anno completo
time_days = (1:8760) / 24;  % Converti ore in giorni

% Nomi dei mesi per le etichette
month_names = {'Gen', 'Feb', 'Mar', 'Apr', 'Mag', 'Giu', 'Lug', 'Ago', 'Set', 'Ott', 'Nov', 'Dic'};
month_days = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334, 365];

% Colori per le diverse configurazioni
colors = lines(nCfg504);

for i = 1:nCfg504
    fileIdx = idx504(i);
    fpath = fullfile(pvFiles(fileIdx).folder, pvFiles(fileIdx).name);
    currentTilt = tilts504(i);
    
    fprintf('\nProcessando: %s (Tilt = %d°)\n', pvFiles(fileIdx).name, currentTilt);
    
    % Leggi produzione PV
    TTpv = readPVsystHourlyCSV(fpath);
    pv_kWh = TTpv.E_kWh;
    
    % Calcola capacità batteria e SOC
    [BESS_min, SOC_history] = findMinBatteryCapacity(load_kWh, pv_kWh, BATT_EFF, SOC_MIN, SOC_MAX);
    
    % Calcola bilancio energetico
    net_energy = pv_kWh - load_kWh;  % Positivo = surplus, Negativo = deficit
    
    fprintf('  BESS minima: %.2f kWh\n', BESS_min);
    fprintf('  Produzione PV annua: %.2f kWh\n', sum(pv_kWh));
    
    %% === FIGURA 1: ANNO COMPLETO - CONSUMI E PRODUZIONE ===
    figure('Position', [50 50 1600 900], 'Name', sprintf('504 Moduli - Tilt %d° - Anno Completo', currentTilt));
    
    % Subplot 1: Consumi vs Produzione PV
    subplot(3,1,1);
    hold on;
    area(time_days, load_kWh, 'FaceColor', [1 0.3 0.3], 'FaceAlpha', 0.4, 'EdgeColor', 'r', 'LineWidth', 0.5, 'DisplayName', 'Consumi');
    area(time_days, pv_kWh, 'FaceColor', [0.3 0.5 1], 'FaceAlpha', 0.4, 'EdgeColor', 'b', 'LineWidth', 0.5, 'DisplayName', 'Produzione PV');
    grid on;
    xlabel('Tempo [giorni]');
    ylabel('Energia [kWh]');
    title(sprintf('Consumi e Produzione PV - 504 Moduli, Inclinazione %d°', currentTilt), 'FontSize', 12, 'FontWeight', 'bold');
    legend('Location', 'best');
    xlim([1 365]);
    set(gca, 'XTick', month_days(1:end-1)+15, 'XTickLabel', month_names);
    
    % Subplot 2: Bilancio energetico (surplus/deficit)
    subplot(3,1,2);
    hold on;
    pos_energy = max(net_energy, 0);
    neg_energy = min(net_energy, 0);
    bar(time_days, pos_energy, 1, 'FaceColor', [0.2 0.8 0.2], 'EdgeColor', 'none', 'DisplayName', 'Surplus (carica)');
    bar(time_days, neg_energy, 1, 'FaceColor', [0.8 0.2 0.2], 'EdgeColor', 'none', 'DisplayName', 'Deficit (scarica)');
    grid on;
    xlabel('Tempo [giorni]');
    ylabel('Energia [kWh]');
    title('Bilancio Energetico: Surplus/Deficit', 'FontSize', 12, 'FontWeight', 'bold');
    legend('Location', 'best');
    xlim([1 365]);
    set(gca, 'XTick', month_days(1:end-1)+15, 'XTickLabel', month_names);
    
    % Subplot 3: Stato di Carica Batteria
    subplot(3,1,3);
    hold on;
    fill([time_days, fliplr(time_days)], [SOC_history', SOC_MIN*100*ones(1,8760)], [0.5 0.8 0.5], 'FaceAlpha', 0.3, 'EdgeColor', 'none');
    plot(time_days, SOC_history, 'g-', 'LineWidth', 1.5, 'DisplayName', 'SOC');
    yline(SOC_MIN * 100, 'r--', 'LineWidth', 2, 'DisplayName', sprintf('SOC min (%.0f%%)', SOC_MIN*100));
    yline(SOC_MAX * 100, 'r--', 'LineWidth', 2, 'DisplayName', sprintf('SOC max (%.0f%%)', SOC_MAX*100));
    grid on;
    xlabel('Tempo [giorni]');
    ylabel('SOC [%]');
    title(sprintf('Stato di Carica Batteria - Capacità: %.1f kWh', BESS_min), 'FontSize', 12, 'FontWeight', 'bold');
    legend('', 'SOC', sprintf('SOC min (%.0f%%)', SOC_MIN*100), sprintf('SOC max (%.0f%%)', SOC_MAX*100), 'Location', 'best');
    xlim([1 365]);
    ylim([0 100]);
    set(gca, 'XTick', month_days(1:end-1)+15, 'XTickLabel', month_names);
    
    % Aggiusta spaziatura subplots
    sgtitle(sprintf('Analisi Batteria - 504 Moduli, Tilt %d°, BESS %.1f kWh', currentTilt, BESS_min), 'FontSize', 14, 'FontWeight', 'bold');
    
    %% === FIGURA 2: DETTAGLIO STAGIONALE ===
    figure('Position', [100 100 1600 800], 'Name', sprintf('504 Moduli - Tilt %d° - Dettaglio Stagionale', currentTilt));
    
    % Definisci periodi stagionali (indici orari)
    seasons = struct();
    seasons.inverno = 1:24*59;                    % Gen-Feb
    seasons.primavera = 24*59+1:24*151;           % Mar-Mag
    seasons.estate = 24*151+1:24*243;             % Giu-Ago
    seasons.autunno = 24*243+1:24*334;            % Set-Nov
    
    season_names = {'Inverno (Gen-Feb)', 'Primavera (Mar-Mag)', 'Estate (Giu-Ago)', 'Autunno (Set-Nov)'};
    season_fields = fieldnames(seasons);
    
    for s = 1:4
        idx_season = seasons.(season_fields{s});
        time_season = (1:numel(idx_season)) / 24;
        
        subplot(2,2,s);
        hold on;
        
        % Plot SOC
        plot(time_season, SOC_history(idx_season), 'g-', 'LineWidth', 1.5);
        yline(SOC_MIN * 100, 'r--', 'LineWidth', 1.5);
        yline(SOC_MAX * 100, 'r--', 'LineWidth', 1.5);
        
        grid on;
        xlabel('Giorni');
        ylabel('SOC [%]');
        title(season_names{s}, 'FontSize', 11, 'FontWeight', 'bold');
        ylim([0 100]);
    end
    
    sgtitle(sprintf('Dettaglio SOC Stagionale - 504 Moduli, Tilt %d°', currentTilt), 'FontSize', 14, 'FontWeight', 'bold');
    
end

%% 4) CONFRONTO TRA TUTTE LE INCLINAZIONI (504 moduli)
figure('Position', [150 150 1400 600], 'Name', '504 Moduli - Confronto Inclinazioni');

% Calcola e memorizza tutti i SOC
all_SOC = zeros(8760, nCfg504);
all_BESS = zeros(nCfg504, 1);

for i = 1:nCfg504
    fileIdx = idx504(i);
    fpath = fullfile(pvFiles(fileIdx).folder, pvFiles(fileIdx).name);
    
    TTpv = readPVsystHourlyCSV(fpath);
    pv_kWh = TTpv.E_kWh;
    
    [BESS_min, SOC_history] = findMinBatteryCapacity(load_kWh, pv_kWh, BATT_EFF, SOC_MIN, SOC_MAX);
    
    all_SOC(:, i) = SOC_history;
    all_BESS(i) = BESS_min;
end

% Plot confronto SOC
subplot(1,2,1);
hold on;
for i = 1:nCfg504
    plot(time_days, all_SOC(:,i), 'LineWidth', 1.2, 'DisplayName', sprintf('Tilt %d° (BESS=%.0f kWh)', tilts504(i), all_BESS(i)));
end
yline(SOC_MIN * 100, 'k--', 'LineWidth', 1.5, 'HandleVisibility', 'off');
yline(SOC_MAX * 100, 'k--', 'LineWidth', 1.5, 'HandleVisibility', 'off');
grid on;
xlabel('Tempo [giorni]');
ylabel('SOC [%]');
title('Confronto SOC - Diverse Inclinazioni', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best');
xlim([1 365]);
ylim([0 100]);
set(gca, 'XTick', month_days(1:end-1)+15, 'XTickLabel', month_names);

% Grafico a barre BESS minima
subplot(1,2,2);
bar(tilts504, all_BESS, 'FaceColor', [0.3 0.6 0.9]);
grid on;
xlabel('Inclinazione [°]');
ylabel('Capacità BESS [kWh]');
title('Capacità Batteria Minima vs Inclinazione', 'FontSize', 12, 'FontWeight', 'bold');
for i = 1:nCfg504
    text(tilts504(i), all_BESS(i) + 10, sprintf('%.0f', all_BESS(i)), 'HorizontalAlignment', 'center', 'FontSize', 10, 'FontWeight', 'bold');
end

sgtitle('Confronto Configurazioni 504 Moduli - Diverse Inclinazioni', 'FontSize', 14, 'FontWeight', 'bold');

fprintf('\n=== RIEPILOGO 504 MODULI ===\n');
T = table(tilts504, invPower504, all_BESS, 'VariableNames', {'Tilt_deg', 'InvPower_kW', 'BESS_min_kWh'});
T = sortrows(T, 'Tilt_deg');
disp(T);

%% 5) GRAFICO GENNAIO - TUTTE LE CONFIGURAZIONI
figure('Position', [200 100 1600 900], 'Name', '504 Moduli - Gennaio - Tutte le Configurazioni');

% Indici per gennaio (ore 1-744, giorni 1-31)
idx_jan = 1:744;
time_jan = (1:744) / 24;  % Tempo in giorni

% Colori per le diverse inclinazioni
colors = lines(nCfg504);

% Subplot 1: Consumi (uguale per tutte le configurazioni)
subplot(2,1,1);
hold on;
area(time_jan, load_kWh(idx_jan), 'FaceColor', [1 0.3 0.3], 'FaceAlpha', 0.5, 'EdgeColor', 'r', 'LineWidth', 0.5, 'DisplayName', 'Consumi');

% Sovrapponi produzione PV per ogni configurazione
for i = 1:nCfg504
    fileIdx = idx504(i);
    fpath = fullfile(pvFiles(fileIdx).folder, pvFiles(fileIdx).name);
    TTpv = readPVsystHourlyCSV(fpath);
    pv_kWh = TTpv.E_kWh;
    
    plot(time_jan, pv_kWh(idx_jan), 'Color', colors(i,:), 'LineWidth', 1.5, ...
        'DisplayName', sprintf('PV Tilt %d°', tilts504(i)));
end

grid on;
xlabel('Tempo [giorni di Gennaio]');
ylabel('Energia [kWh]');
title('Consumi e Produzione PV - Gennaio - 504 Moduli, Tutte le Inclinazioni', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best');
xlim([0 31]);
set(gca, 'XTick', 1:2:31);

% Subplot 2: Dettaglio produzione PV (senza consumi per vedere meglio le differenze)
subplot(2,1,2);
hold on;

for i = 1:nCfg504
    fileIdx = idx504(i);
    fpath = fullfile(pvFiles(fileIdx).folder, pvFiles(fileIdx).name);
    TTpv = readPVsystHourlyCSV(fpath);
    pv_kWh = TTpv.E_kWh;
    
    % Calcola energia totale gennaio
    pv_jan_total = sum(pv_kWh(idx_jan));
    
    plot(time_jan, pv_kWh(idx_jan), 'Color', colors(i,:), 'LineWidth', 1.5, ...
        'DisplayName', sprintf('Tilt %d° (Tot: %.0f kWh)', tilts504(i), pv_jan_total));
end

grid on;
xlabel('Tempo [giorni di Gennaio]');
ylabel('Energia [kWh]');
title('Confronto Produzione PV - Gennaio - Diverse Inclinazioni', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best');
xlim([0 31]);
set(gca, 'XTick', 1:2:31);

sgtitle('Analisi Gennaio - 504 Moduli, Confronto Inclinazioni', 'FontSize', 14, 'FontWeight', 'bold');

% Stampa riepilogo gennaio
fprintf('\n=== PRODUZIONE GENNAIO - 504 MODULI ===\n');
jan_totals = zeros(nCfg504, 1);
for i = 1:nCfg504
    fileIdx = idx504(i);
    fpath = fullfile(pvFiles(fileIdx).folder, pvFiles(fileIdx).name);
    TTpv = readPVsystHourlyCSV(fpath);
    jan_totals(i) = sum(TTpv.E_kWh(idx_jan));
end
load_jan_total = sum(load_kWh(idx_jan));
fprintf('Consumi Gennaio: %.2f kWh\n', load_jan_total);
T_jan = table(tilts504, jan_totals, jan_totals - load_jan_total, ...
    'VariableNames', {'Tilt_deg', 'Produzione_kWh', 'Bilancio_kWh'});
T_jan = sortrows(T_jan, 'Tilt_deg');
disp(T_jan);

fprintf('\nGenerati grafici per %d configurazioni con 504 moduli.\n', nCfg504);

% Mantieni le figure aperte
disp('Grafici generati e visualizzati.');
