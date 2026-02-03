%% MAIN_BATTERY.m
% Script per confrontare diverse configurazioni di impianti fotovoltaici
% Obiettivo: trovare la configurazione che minimizza l'energia non coperta
% 
% Input:
%   - Consumi.csv: consumi orari dell'edificio (8760 ore)
%   - PVsyst results/*.CSV: file PVsyst con produzione oraria per ogni configurazione
%
% Output:
%   - results_unmet_load.csv: tabella con energia non coperta per ogni configurazione

clear; clc;

%% === PARAMETRI ECONOMICI ===
% Costi dei componenti dell'impianto [€]
COST_PV = 100;      % Costo pannelli fotovoltaici [€/modulo]
COST_INV = 50;    % Costo inverter [€/kW]
COST_BATT = 120;   % Costo batteria [€/kWh]
COST_EL = 0.22;    % Costo energia elettrica [€/kWh]
CONS_1Y = 100669;     % Consumo annuo [kWh]
OPEX_RATE = 0.02;    % OPEX annuo come % del CAPEX (3%)
TASSO_INF = 0.02;
DMR = 0.04;          % Discount Market Rate
YEAR = 25;           % Anni di simulazione

% Parametri batteria
BATT_EFF = 0.95;     % Efficienza carica/scarica batteria (95%)
SOC_MIN = 0.3;       % State of Charge minimo (30%)
SOC_MAX = 0.8;       % State of Charge massimo (80%)

% Calcola costo annuo senza PV (baseline)
Costo_annuo = CONS_1Y * COST_EL;  

%% === PATH FILES ===
loadFile  = "C:\Users\scimo\OneDrive\Desktop\PoliMi\Secondo Anno\Solar and Biomass\Project\Matlab project\Consumi.csv";
pvFolder  = "C:\Users\scimo\OneDrive\Desktop\PoliMi\Secondo Anno\Solar and Biomass\Project\Matlab project\PVsyst results";
pvPattern = "*.CSV";  % Pattern per trovare tutti i CSV PVsyst

%% 1) CARICAMENTO CONSUMI ORARI
% Legge il file CSV con i consumi dell'edificio
Tload = readtable(loadFile);

% Trova automaticamente la prima colonna numerica (assumo sia quella dei consumi)
numCols = varfun(@isnumeric, Tload, "OutputFormat", "uniform");
idxLoad = find(numCols, 1, "first");
assert(~isempty(idxLoad), "Nessuna colonna numerica nel CSV consumi.");

% Estrae i valori di consumo in kWh
load_kWh_START = double(Tload{:, idxLoad});
load_kWh = load_kWh_START*1.125;

% Verifica che ci siano esattamente 8760 ore (1 anno)
assert(numel(load_kWh) == 8760, "Consumi: attese 8760 righe, trovate %d", numel(load_kWh));
assert(all(isfinite(load_kWh)), "Consumi: trovati NaN/Inf.");

%% 2) RICERCA FILE PVSYST (CONFIGURAZIONI)
% Trova tutti i file CSV nella cartella PVsyst results
pvFiles = dir(fullfile(pvFolder, pvPattern));
assert(~isempty(pvFiles), "Nessun file PV trovato in %s", pvFolder);

nCfg = numel(pvFiles);  % Numero di configurazioni da confrontare

%% 3) ESTRAZIONE PARAMETRI DA TUTTI I FILE
% Prima estrai tutti i numeri di moduli, inclinazioni e potenza inverter dai nomi file
% Formato: Salvaplast_Project_VC2_HourlyRes_506_0_300
% dove 506=moduli, 0=inclinazione, 300=potenza_inverter_kW
allModules = zeros(nCfg, 1);
allTilts = zeros(nCfg, 1);
allInvPower = zeros(nCfg, 1);

for i = 1:nCfg
    % Formato: HourlyRes_<moduli>_<inclinazione>_<potenza_inverter_kW>
    tokens = regexp(pvFiles(i).name, 'HourlyRes_(\d+)_(\d+)_(\d+)', 'tokens');
    if ~isempty(tokens)
        allModules(i) = str2double(tokens{1}{1});
        allTilts(i) = str2double(tokens{1}{2});
        allInvPower(i) = str2double(tokens{1}{3});  % Potenza in kW
    else
        error('Nome file non nel formato atteso: %s. Formato richiesto: ...HourlyRes_<moduli>_<inclinazione>_<potenza_kW>\nEsempio: Salvaplast_Project_VC2_HourlyRes_506_0_300', pvFiles(i).name);
    end
end

% Trova valori unici di moduli e inclinazioni
uniqueModules = unique(allModules);
nModulesValues = numel(uniqueModules);
uniqueInvPower = unique(allInvPower);

fprintf('\n=== CONFIGURAZIONI TROVATE ===\n');
fprintf('Numero di moduli unici: %d valori -> [%s]\n', nModulesValues, num2str(uniqueModules'));
fprintf('Potenze inverter uniche: %d valori -> [%s] kW\n', numel(uniqueInvPower), num2str(uniqueInvPower'));
fprintf('File totali da processare: %d\n', nCfg);

% Preallocazione array risultati
cfgNames   = strings(nCfg, 1);   % Nomi delle configurazioni
unmet_kWh  = zeros(nCfg, 1);     % Energia non coperta per ogni config
nModules   = zeros(nCfg, 1);     % Numero moduli per ogni config
invPower_kW = zeros(nCfg, 1);    % Potenza totale inverter [kW]
tilt       = zeros(nCfg, 1);     % Inclinazione pannelli [gradi]
PV_prod_kWh = zeros(nCfg, 1);   % Energia prodotta annualmente dai pannelli [kWh]
BESS_min   = zeros(nCfg, 1);     % Capacità minima batteria [kWh]
SAVINGS_Y1 = zeros(nCfg, 1);     % Risparmio anno 1 [€]
OPEX       = zeros(nCfg, 1);     % Costi operativi annui [€/anno]
NPV        = zeros(nCfg, 1);     % Net Present Value [€]
LCOE       = zeros(nCfg, 1);     % Levelized Cost of Energy [€/kWh]

%% 4) LOOP ANNIDATO: MODULI → INCLINAZIONI
% Ciclo esterno: varia numero moduli
% Ciclo interno: varia inclinazione per quel numero di moduli

idx_global = 0;  % Indice globale per salvare risultati

for iMod = 1:nModulesValues
    currentModules = uniqueModules(iMod);
    
    % Trova tutti i file con questo numero di moduli
    idxFiles = find(allModules == currentModules);
    tiltsForThisModule = allTilts(idxFiles);
    
    fprintf('\n\n╔════════════════════════════════════════════════════╗\n');
    fprintf('║ MODULI: %d (%d configurazioni con diverse inclinazioni) ║\n', currentModules, numel(idxFiles));
    fprintf('╚════════════════════════════════════════════════════╝\n');
    
    % Ciclo interno: varia inclinazione per questo numero di moduli
    for iTilt = 1:numel(idxFiles)
        idx_global = idx_global + 1;
        fileIdx = idxFiles(iTilt);
        
        fpath = fullfile(pvFiles(fileIdx).folder, pvFiles(fileIdx).name);
        currentTilt = tiltsForThisModule(iTilt);
        
        fprintf('\n  → [%d/%d] Inclinazione: %d° | File: %s\n', iTilt, numel(idxFiles), currentTilt, pvFiles(fileIdx).name);
        
        % Salva parametri dal nome file
        nModules(idx_global) = currentModules;
        tilt(idx_global) = currentTilt;
        invPower_kW(idx_global) = allInvPower(fileIdx);  % Potenza dal nome file
    
        % === LETTURA PRODUZIONE PV ===
        % Legge il file PVsyst e estrae solo la produzione oraria
        TTpv = readPVsystHourlyCSV(fpath);
        pv_kWh = TTpv.E_kWh;  % Energia prodotta ogni ora [kWh]
        
        fprintf('     Potenza inverter: %.1f kW\n', invPower_kW(idx_global));
        
        % Verifica che anche il PV abbia 8760 ore
        assert(numel(pv_kWh) == 8760, "PV file %s: attese 8760 righe, trovate %d", pvFiles(fileIdx).name, numel(pv_kWh));
        
        % Calcola energia prodotta annualmente
        PV_prod_kWh(idx_global) = sum(pv_kWh);
        
        fprintf('     Produzione PV annuale: %.2f kWh\n', PV_prod_kWh(idx_global));
        
        % === CALCOLO DEFICIT SENZA BATTERIA ===
        deficit_kWh_no_batt = max(load_kWh - pv_kWh, 0);
        unmet_kWh(idx_global) = sum(deficit_kWh_no_batt);
        
        fprintf('     Unmet load (no battery): %.2f kWh\n', unmet_kWh(idx_global));
        
        % === TROVA CAPACITÀ MINIMA BATTERIA ===
        [BESS_min(idx_global), SOC_history] = findMinBatteryCapacity(load_kWh, pv_kWh, BATT_EFF, SOC_MIN, SOC_MAX);
        
        fprintf('     BESS minima: %.2f kWh\n', BESS_min(idx_global));
        
        % Salva il nome della configurazione (senza estensione)
        [~, name, ~] = fileparts(pvFiles(fileIdx).name);
        cfgNames(idx_global) = string(name);
        
        %% CALCOLO ECONOMICO
        IC = (COST_PV * nModules(idx_global) + COST_INV * invPower_kW(idx_global))*2 + COST_BATT * BESS_min(idx_global);
        
        % Con batteria ottimale, unmet load = 0 (assumo)
        SAVINGS_Y1(idx_global) = Costo_annuo;  % Risparmio totale (nessun acquisto rete)
        
        % OPEX = 3% del CAPEX annuo
        OPEX(idx_global) = OPEX_RATE * IC;
        
        % LCOE con CAPEX annualizzato (Capital Recovery Factor)
        % CRF = [r * (1+r)^n] / [(1+r)^n - 1]
        CRF = (DMR * (1 + DMR)^YEAR) / ((1 + DMR)^YEAR - 1);
        CAPEX_annualizzato = IC * CRF;
        LCOE(idx_global) = (CAPEX_annualizzato + OPEX(idx_global)) /CONS_1Y;
        
        % NPV considerando anche gli OPEX annuali
        % Net benefit annuale = SAVINGS - OPEX
        Net_benefit_Y1 = SAVINGS_Y1(idx_global) - OPEX(idx_global);
        NPV(idx_global) = -IC + Net_benefit_Y1 * (1/(DMR - TASSO_INF)) * (1 - ((1 + TASSO_INF)/(1 + DMR))^YEAR);
        
        fprintf('     Investment Cost: %.2f €\n', IC);
        fprintf('     OPEX (annuo): %.2f €/y\n', OPEX(idx_global));
        fprintf('     Savings Y1: %.2f €/y\n', SAVINGS_Y1(idx_global));
        fprintf('     Net Benefit Y1: %.2f €/y\n', Net_benefit_Y1);
        fprintf('     LCOE: %.4f €/kWh\n', LCOE(idx_global));
        fprintf('     NPV (20y): %.2f €\n', NPV(idx_global));
        
        % %% === PLOT GENNAIO (TUTTE LE CONFIGURAZIONI) ===
        % % Gennaio: ore 1-744 (31 giorni * 24 ore)
        % idx_jan = 1:744;
    %
        % % Crea vettore temporale (giorni)
        % time_jan = (1:744) / 24;  % Converti ore in giorni
        %     
        %     % Estrai dati gennaio
        %     load_jan = load_kWh(idx_jan);
        %     pv_jan = pv_kWh(idx_jan);
        %     soc_jan = SOC_history(idx_jan);
        %     
        %     % Crea figura
        %     figure('Position', [100 100 1200 800]);
        %     
        %     % Subplot 1: Consumi e Produzione
        %     subplot(2,1,1);
        %     hold on;
        %     plot(time_jan, load_jan, 'r-', 'LineWidth', 1.5, 'DisplayName', 'Consumi');
        %     plot(time_jan, pv_jan, 'b-', 'LineWidth', 1.5, 'DisplayName', 'Produzione PV');
        %     grid on;
        %     xlabel('Tempo [giorni]');
        %     ylabel('Energia [kWh]');
        %     title(sprintf('Consumi e Produzione PV - Gennaio - Config: %s', name));
        %     legend('Location', 'best');
        %     xlim([1 31]);
        %     
        %     % Subplot 2: Stato di Carica Batteria
        %     subplot(2,1,2);
        %     plot(time_jan, soc_jan, 'g-', 'LineWidth', 2);
        %     grid on;
        %     xlabel('Tempo [giorni]');
        %     ylabel('SOC [%]');
        %     title(sprintf('Stato di Carica Batteria (Cap: %.1f kWh)', BESS_min(idx_global)));
        %     xlim([1 31]);
        %     ylim([0 100]);
        %     
        %     % Aggiungi linee SOC min/max
        %     hold on;
        %     yline(SOC_MIN * 100, 'r--', 'LineWidth', 1.5, 'DisplayName', 'SOC min');
        %     yline(SOC_MAX * 100, 'r--', 'LineWidth', 1.5, 'DisplayName', 'SOC max');
        %     legend('SOC', 'SOC min', 'SOC max', 'Location', 'best');
        %     
        %     % Salva figura
        %     % plotName = sprintf('plot_gennaio_%s.png', strrep(name, ' ', '_'));
        %     % saveas(gcf, plotName);
        %     % close(gcf);  % Chiudi la figura per liberare memoria
        %     % fprintf('     Plot gennaio salvato in: %s\n', plotName);
        %
        % %% === PLOT ANNO COMPLETO (TUTTE LE CONFIGURAZIONI) ===
        % % Anno completo: tutte le 8760 ore
        % idx_year = 1:8760;
        % 
        % % Crea vettore temporale (giorni)
        % time_days = (1:8760) / 24;  % Converti ore in giorni (0-365)
        % 
        % % Estrai dati anno completo
        % load_year = load_kWh(idx_year);
        % pv_year = pv_kWh(idx_year);
        % soc_year = SOC_history(idx_year);
        % 
        % % Crea figura
        % figure('Position', [100 100 1400 900]);
        % 
        % % Subplot 1: Consumi e Produzione
        % subplot(2,1,1);
        % hold on;
        % plot(time_days, load_year, 'r-', 'LineWidth', 1, 'DisplayName', 'Consumi');
        % plot(time_days, pv_year, 'b-', 'LineWidth', 1, 'DisplayName', 'Produzione PV');
        % grid on;
        % xlabel('Tempo [giorni]');
        % ylabel('Energia [kWh]');
        % title(sprintf('Consumi e Produzione PV - Anno Completo - Config: %s', name));
        % legend('Location', 'best');
        % xlim([1 365]);
        % 
        % % Subplot 2: Stato di Carica Batteria
        % subplot(2,1,2);
        % plot(time_days, soc_year, 'g-', 'LineWidth', 1.5);
        % grid on;
        % xlabel('Tempo [giorni]');
        % ylabel('SOC [%]');
        % title(sprintf('Stato di Carica Batteria - Anno Completo (Cap: %.1f kWh)', BESS_min(idx_global)));
        % xlim([1 365]);
        % ylim([0 100]);
        % 
        % % Aggiungi linee SOC min/max
        % hold on;
        % yline(SOC_MIN * 100, 'r--', 'LineWidth', 1.5);
        % yline(SOC_MAX * 100, 'r--', 'LineWidth', 1.5);
        % legend('SOC', sprintf('SOC min (%.0f%%)', SOC_MIN*100), sprintf('SOC max (%.0f%%)', SOC_MAX*100), 'Location', 'best');

        % Salva figura
        % plotName = sprintf('plot_anno_completo_%s.png', strrep(name, ' ', '_'));
        % saveas(gcf, plotName);
        % close(gcf);  % Chiudi la figura per liberare memoria
        % fprintf('     Plot anno completo salvato in: %s\n', plotName);
    end  % Fine ciclo interno (inclinazioni)
end  % Fine ciclo esterno (moduli)

%% 5) OUTPUT RISULTATI
% Crea tabella con tutti i dati
Results = table(cfgNames, nModules, tilt, invPower_kW, PV_prod_kWh, BESS_min, unmet_kWh, SAVINGS_Y1, OPEX, LCOE, NPV, ...
    'VariableNames', {'Config','N_Modules','Tilt_deg','InvPower_kW','PV_Production_kWh','BESS_min_kWh','UnmetLoad_noBatt_kWh','Savings_EUR','OPEX_EUR','LCOE_EUR_kWh','NPV_EUR'});

% Ordina dal migliore NPV al peggiore
Results = sortrows(Results, 'NPV_EUR', 'descend');

% Stampa a schermo
fprintf('\n\n=== RISULTATI FINALI ===\n');
disp(Results);

% Salva su file CSV
writetable(Results, "results_unmet_load.csv");
fprintf('Salvato in: results_unmet_load.csv\n');

%% 6) GRAFICO 3D: MODULI vs INCLINAZIONE vs NPV
figure('Position', [100 100 1200 900]);

uniqueTilts_3D = unique(tilt);
uniqueModules_3D = unique(nModules);

[T_grid, M_grid] = meshgrid(uniqueTilts_3D, uniqueModules_3D);

% Interpola NPV sulla griglia (attenzione all’ordine!)
Z_grid = griddata(tilt, nModules, LCOE, T_grid, M_grid, 'natural'); % 'natural' più stabile di 'cubic'

% Superficie: X=Moduli, Y=Tilt
surf(M_grid, T_grid, Z_grid, 'FaceAlpha', 0.6, 'EdgeColor', 'none');
hold on;

scatter3(nModules, tilt, LCOE, 150, LCOE, 'filled', ...
    'MarkerEdgeColor', 'k', 'LineWidth', 1.5);

grid on;
xlabel('Numero Moduli', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('Inclinazione [°]', 'FontSize', 12, 'FontWeight', 'bold');
zlabel('NPV [k€]', 'FontSize', 12, 'FontWeight', 'bold');
title('Analisi Configurazioni: NPV vs Moduli vs Inclinazione', 'FontSize', 14, 'FontWeight', 'bold');

c = colorbar;
c.Label.String = 'LCOE [€kWh]';
c.Label.FontSize = 11;
colormap(jet);

view(-37.5, 30);
lighting gouraud;
camlight('headlight');

[~, topIdx] = maxk(NPV, 3);
for i = 1:3
    text(nModules(topIdx(i)), tilt(topIdx(i)), LCOE(topIdx(i)), ...
        sprintf(' Top %d\n %.0f mod, %.0f°\n %.1f k€', i, nModules(topIdx(i)), tilt(topIdx(i)), LCOE(topIdx(i))), ...
        'FontSize', 9, 'FontWeight', 'bold', 'Color', 'red', ...
        'BackgroundColor', [1 1 1 0.7], 'EdgeColor', 'red');
end


%% 7) GRAFICO 2D: HEATMAP NPV
% Crea matrice per heatmap (se dati su griglia regolare)
uniqueTilts = unique(tilt);
nTilts = numel(uniqueTilts);

% Crea matrice NPV [moduli x inclinazioni]
NPV_matrix = nan(nModulesValues, nTilts);

for i = 1:numel(nModules)
    idxMod = find(uniqueModules == nModules(i), 1);
    idxTilt = find(uniqueTilts == tilt(i), 1);
    if ~isempty(idxMod) && ~isempty(idxTilt)
        NPV_matrix(idxMod, idxTilt) = NPV(i);
    end
end

figure('Position', [100 100 1000 700]);
imagesc(uniqueTilts, uniqueModules, NPV_matrix/1000);
set(gca, 'YDir', 'normal');
colorbar;
colormap(jet);

xlabel('Inclinazione [°]', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('Numero Moduli', 'FontSize', 12, 'FontWeight', 'bold');
title('Heatmap NPV: Moduli vs Inclinazione', 'FontSize', 14, 'FontWeight', 'bold');
c = colorbar;
c.Label.String = 'NPV [k€]';
c.Label.FontSize = 11;

% Aggiungi valori numerici nelle celle
hold on;
for i = 1:nModulesValues
    for j = 1:nTilts
        if ~isnan(NPV_matrix(i,j))
            text(uniqueTilts(j), uniqueModules(i), sprintf('%.1f', NPV_matrix(i,j)/1000), ...
                'HorizontalAlignment', 'center', 'FontSize', 9, 'FontWeight', 'bold', 'Color', 'white');
        end
    end
end

% Salva figura
% saveas(gcf, 'plot_heatmap_NPV.png');
% fprintf('Heatmap NPV salvata in: plot_heatmap_NPV.png\n');

%% GRAFICO LCOE vs NPV - Confronto a Barre
figure('Position', [100 100 1400 700]);

% Crea etichette per le configurazioni (Moduli_Tilt)
config_labels = strings(nCfg, 1);
for i = 1:nCfg
    config_labels(i) = sprintf('%d mod\n%d°', nModules(i), tilt(i));
end

% Ordina per numero di moduli e poi per tilt
[~, sort_idx] = sortrows([nModules, tilt]);
config_labels_sorted = config_labels(sort_idx);
NPV_sorted = NPV(sort_idx) / 1000;  % Converti in k€
LCOE_sorted = LCOE(sort_idx) * 1000;  % Converti in €/MWh per scala comparabile

% Subplot 1: NPV per configurazione
subplot(2,1,1);
bar_npv = bar(categorical(config_labels_sorted, config_labels_sorted), NPV_sorted, 'FaceColor', [0.2 0.6 0.8]);
grid on;
ylabel('NPV [k€]', 'FontSize', 11, 'FontWeight', 'bold');
title('NPV per Configurazione', 'FontSize', 12, 'FontWeight', 'bold');
% Colora barre in base al valore
for i = 1:length(NPV_sorted)
    if NPV_sorted(i) == max(NPV_sorted)
        bar_npv.FaceColor = 'flat';
        bar_npv.CData(i,:) = [0.2 0.8 0.2];  % Verde per il massimo
    end
end

% Subplot 2: LCOE per configurazione
subplot(2,1,2);
bar_lcoe = bar(categorical(config_labels_sorted, config_labels_sorted), LCOE_sorted, 'FaceColor', [0.9 0.4 0.3]);
grid on;
ylabel('LCOE [€/MWh]', 'FontSize', 11, 'FontWeight', 'bold');
xlabel('Configurazione (Moduli, Inclinazione)', 'FontSize', 11, 'FontWeight', 'bold');
title('LCOE per Configurazione', 'FontSize', 12, 'FontWeight', 'bold');
% Colora barre in base al valore
for i = 1:length(LCOE_sorted)
    if LCOE_sorted(i) == min(LCOE_sorted)
        bar_lcoe.FaceColor = 'flat';
        bar_lcoe.CData(i,:) = [0.2 0.8 0.2];  % Verde per il minimo
    end
end

sgtitle('Confronto NPV e LCOE per Tutte le Configurazioni', 'FontSize', 14, 'FontWeight', 'bold');

% Salva figura
% saveas(gcf, 'plot_LCOE_vs_NPV.png');
% fprintf('Grafico LCOE vs NPV salvato in: plot_LCOE_vs_NPV.png\n');