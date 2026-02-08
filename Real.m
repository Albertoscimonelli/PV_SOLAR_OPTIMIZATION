clear; clc;
close all;

%% ========================================================================
%  PARAMETRI ECONOMICI (NUOVA STRUTTURA COSTI) + PARAMETRI TECNICI BATTERIA
%  ========================================================================

% --- Orizzonte e tassi ---
YEAR = 25;           % [anni]
DMR  = 0.04;         % discount rate (se = 0 -> non-discount)
TASSO_INF = 0.03;    % inflazione (usata SOLO per escalation dei savings, se vuoi)

% --- Prezzi energia / baseline ---
COST_EL = 0.22;        % [€/kWh] costo acquisto rete
PREZZO_VENDITA = 0.10; % [€/kWh] prezzo vendita energia in eccesso
CONS_1Y = 100669;      % [kWh] consumo annuo

% --- Potenza modulo (dato da te) ---
Pmod_Wp = 600;         % [Wp] potenza di picco modulo

% --- Parametri batteria ---
BATT_EFF = 0.95;     % Efficienza carica/scarica batteria
SOC_MIN  = 0.3;      % SOC minimo
SOC_MAX  = 0.8;      % SOC massimo

% Baseline costo annuo senza PV
Costo_annuo = CONS_1Y * COST_EL;

% --- COST STRUCT (coefficenti e parametri modificabili) ---
cost = struct();

% CAPEX variabile
cost.C_PV_EUR_per_kWp   = 1100;  % [€/kWp] PV turnkey (range tipico 900–1300)
cost.C_BESS_EUR_per_kWh = 450;   % [€/kWh] BESS installed (range tipico 300–600)

% PCS / inverter bidirezionale (qui usiamo invPower_kW come PCS)
cost.include_PCS_in_BESS = false;
cost.C_PCS_EUR_per_kW    = 180;  % [€/kW] solo se include_PCS_in_BESS=false

% CAPEX fisso (lump sums)
cost.engineering_and_permitting_EUR      = 5000;
cost.main_switchboard_and_grounding_EUR  = 3000;
cost.monitoring_EUR                      = 1000;
cost.logistics_site_safety_EUR           = 2000;

% Contingenze
cost.contingency_rate = 0.07;  % 7%

% OPEX annuo
cost.OPEX_PV_rate   = 0.012; % 1.2%/y del CAPEX FV
cost.OPEX_BESS_rate = 0.010; % 1.0%/y del CAPEX BESS
cost.insurance_rate = 0.0;   % opzionale (es. 0.003)

% Replacement
cost.bess_life_years = 11;
cost.bess_replacement_fraction = 0.75;

cost.pcs_life_years = 14;
cost.pcs_replacement_fraction = 0.55;

% Se PCS incluso nel BESS e vuoi comunque replacement su quota equivalente:
cost.pcs_equivalent_CAPEX_EUR_per_kW = 180;

%% ========================================================================
%  PATH FILES
%  ========================================================================
loadFile  = "C:\Users\scimo\OneDrive\Desktop\PoliMi\Secondo Anno\Solar and Biomass\Project\Matlab project\Consumi.csv";
pvFolder  = "C:\Users\scimo\OneDrive\Desktop\PoliMi\Secondo Anno\Solar and Biomass\Project\Matlab project\Nuova cartella";
pvPattern = "*.CSV";  % Pattern per trovare tutti i CSV PVsyst

%% ========================================================================
%  1) CARICAMENTO CONSUMI ORARI
%  ========================================================================
Tload = readtable(loadFile);

% Trova automaticamente la prima colonna numerica
numCols = varfun(@isnumeric, Tload, "OutputFormat", "uniform");
idxLoad = find(numCols, 1, "first");
assert(~isempty(idxLoad), "Nessuna colonna numerica nel CSV consumi.");

load_kWh_START = double(Tload{:, idxLoad});
load_kWh = load_kWh_START * 1.125;  % (tua correzione)

assert(numel(load_kWh) == 8760, "Consumi: attese 8760 righe, trovate %d", numel(load_kWh));
assert(all(isfinite(load_kWh)), "Consumi: trovati NaN/Inf.");

%% ========================================================================
%  2) RICERCA FILE PVSYST (CONFIGURAZIONI)
%  ========================================================================
pvFiles = dir(fullfile(pvFolder, pvPattern));
assert(~isempty(pvFiles), "Nessun file PV trovato in %s", pvFolder);

nCfg = numel(pvFiles);

%% ========================================================================
%  3) ESTRAZIONE PARAMETRI DA TUTTI I FILE (DA NOME FILE)
%  ========================================================================
allModules  = zeros(nCfg, 1);
allTilts    = zeros(nCfg, 1);
allInvPower = zeros(nCfg, 1);

for i = 1:nCfg
    tokens = regexp(pvFiles(i).name, 'HourlyRes_(\d+)_(\d+)_(\d+)', 'tokens');
    if ~isempty(tokens)
        allModules(i)  = str2double(tokens{1}{1});
        allTilts(i)    = str2double(tokens{1}{2});
        allInvPower(i) = str2double(tokens{1}{3});
    else
        error(['Nome file non nel formato atteso: %s.\n' ...
               'Formato richiesto: ...HourlyRes_<moduli>_<inclinazione>_<potenza_kW>\n' ...
               'Esempio: Salvaplast_Project_VC2_HourlyRes_506_0_300'], pvFiles(i).name);
    end
end

uniqueModules  = unique(allModules);
uniqueInvPower = unique(allInvPower);
nModulesValues = numel(uniqueModules);

fprintf('\n=== CONFIGURAZIONI TROVATE ===\n');
fprintf('Numero di moduli unici: %d valori -> [%s]\n', nModulesValues, num2str(uniqueModules'));
fprintf('Potenze inverter uniche: %d valori -> [%s] kW\n', numel(uniqueInvPower), num2str(uniqueInvPower'));
fprintf('File totali da processare: %d\n', nCfg);

% Preallocazione risultati
cfgNames    = strings(nCfg, 1);
unmet_kWh   = zeros(nCfg, 1);
nModules    = zeros(nCfg, 1);
invPower_kW = zeros(nCfg, 1);
tilt        = zeros(nCfg, 1);
PV_prod_kWh = zeros(nCfg, 1);
BESS_min    = zeros(nCfg, 1);
SAVINGS_Y1  = zeros(nCfg, 1);
OPEX        = zeros(nCfg, 1);   % anno 1
NPV         = zeros(nCfg, 1);
LCOE        = zeros(nCfg, 1);

% (opzionale) CAPEX totale per tabella / debug
CAPEX_total = zeros(nCfg, 1);

%% ========================================================================
%  4) LOOP: MODULI → INCLINAZIONI
%  ========================================================================
idx_global = 0;

for iMod = 1:nModulesValues
    currentModules = uniqueModules(iMod);

    idxFiles = find(allModules == currentModules);
    tiltsForThisModule = allTilts(idxFiles);

    fprintf('\n\n╔════════════════════════════════════════════════════╗\n');
    fprintf('║ MODULI: %d (%d configurazioni con diverse inclinazioni) ║\n', currentModules, numel(idxFiles));
    fprintf('╚════════════════════════════════════════════════════╝\n');

    for iTilt = 1:numel(idxFiles)
        idx_global = idx_global + 1;
        fileIdx = idxFiles(iTilt);

        fpath = fullfile(pvFiles(fileIdx).folder, pvFiles(fileIdx).name);
        currentTilt = tiltsForThisModule(iTilt);

        fprintf('\n  → [%d/%d] Inclinazione: %d° | File: %s\n', iTilt, numel(idxFiles), currentTilt, pvFiles(fileIdx).name);

        nModules(idx_global)    = currentModules;
        tilt(idx_global)        = currentTilt;
        invPower_kW(idx_global) = allInvPower(fileIdx);

        % === LETTURA PRODUZIONE PV ===
        TTpv = readPVsystHourlyCSV(fpath);
        pv_kWh = TTpv.E_kWh;

        fprintf('     Potenza inverter (PCS): %.1f kW\n', invPower_kW(idx_global));

        assert(numel(pv_kWh) == 8760, "PV file %s: attese 8760 righe, trovate %d", pvFiles(fileIdx).name, numel(pv_kWh));

        PV_prod_kWh(idx_global) = sum(pv_kWh);
        fprintf('     Produzione PV annuale: %.2f kWh\n', PV_prod_kWh(idx_global));

        % === DEFICIT SENZA BATTERIA ===
        deficit_kWh_no_batt = max(load_kWh - pv_kWh, 0);
        unmet_kWh(idx_global) = sum(deficit_kWh_no_batt);
        fprintf('     Unmet load (no battery): %.2f kWh\n', unmet_kWh(idx_global));

        % === BATTERIA MINIMA ===
        [BESS_min(idx_global), SOC_history] = findMinBatteryCapacity(load_kWh, pv_kWh, BATT_EFF, SOC_MIN, SOC_MAX);
        fprintf('     BESS minima: %.2f kWh\n', BESS_min(idx_global));

        % Nome config
        [~, name, ~] = fileparts(pvFiles(fileIdx).name);
        cfgNames(idx_global) = string(name);

        %% =========================
        %  CALCOLO ECONOMICO NUOVO
        %  =========================

        % Taglie
        P_PV_kWp   = (nModules(idx_global) * Pmod_Wp) / 1000;  % [kWp]
        E_BESS_kWh = BESS_min(idx_global);                     % [kWh]
        P_PCS_kW   = invPower_kW(idx_global);                  % [kW]

        % Energia servita (Scenario 1: assumo copertura totale dei carichi)
        E_served_y = CONS_1Y;

        % Calcolo costi e LCOE
        eco = computeEconomics(P_PV_kWp, E_BESS_kWh, P_PCS_kW, E_served_y, DMR, YEAR, cost);

        CAPEX_total(idx_global) = eco.CAPEX_total;
        OPEX(idx_global)        = eco.OPEX_series(1);   % anno 1
        LCOE(idx_global)        = eco.LCOE;

        % Savings anno 1 (come tuo: niente acquisto rete)
        SAVINGS_Y1(idx_global) = Costo_annuo;

        % NPV: -CAPEX + sum_t [ (Savings_t - OPEX_t - Repl_t) / (1+DMR)^t ]
        if DMR == 0
            disc = ones(YEAR, 1);
        else
            disc = (1 + DMR).^((1:YEAR)');
        end

        savings_series = SAVINGS_Y1(idx_global) * (1 + TASSO_INF).^((1:YEAR)'); % escalation
        net_cf = savings_series - eco.OPEX_series - eco.replacement_series;

        NPV(idx_global) = -eco.CAPEX_total + sum(net_cf ./ disc);

        fprintf('     PV size: %.2f kWp | BESS: %.2f kWh | PCS: %.1f kW\n', P_PV_kWp, E_BESS_kWh, P_PCS_kW);
        fprintf('     CAPEX total: %.2f €\n', eco.CAPEX_total);
        fprintf('     OPEX (year1): %.2f €/y\n', eco.OPEX_series(1));
        fprintf('     LCOE (NPVcost/NPVenergy): %.4f €/kWh\n', eco.LCOE);
        fprintf('     NPV (%dy): %.2f €\n', YEAR, NPV(idx_global));
    end
end

%% ========================================================================
%  5) OUTPUT RISULTATI
%  ========================================================================
Results = table(cfgNames, nModules, tilt, invPower_kW, PV_prod_kWh, BESS_min, unmet_kWh, ...
                CAPEX_total, SAVINGS_Y1, OPEX, LCOE, NPV, ...
    'VariableNames', {'Config','N_Modules','Tilt_deg','InvPower_kW','PV_Production_kWh','BESS_min_kWh', ...
                      'UnmetLoad_noBatt_kWh','CAPEX_EUR','Savings_EUR_Y1','OPEX_EUR_Y1','LCOE_EUR_kWh','NPV_EUR'});

Results = sortrows(Results, 'NPV_EUR', 'descend');

fprintf('\n\n=== RISULTATI FINALI ===\n');
disp(Results);

writetable(Results, "results_unmet_load.csv");
fprintf('Salvato in: results_unmet_load.csv\n');

%% ========================================================================
%  9) ANALISI ECONOMICA DETTAGLIATA - SCENARIO 1 (BESS Ottimale)
%  ========================================================================
[~, bestIdx] = max(NPV);

fprintf('\n\n╔════════════════════════════════════════════════════════════╗\n');
fprintf('║   SCENARIO 1: BESS OTTIMALE (Capacità che azzera unmet load)  ║\n');
fprintf('╚════════════════════════════════════════════════════════════╝\n');
fprintf('Configurazione selezionata: %s\n', cfgNames(bestIdx));
fprintf('  - Moduli: %d\n', nModules(bestIdx));
fprintf('  - Inclinazione: %d°\n', tilt(bestIdx));
fprintf('  - Potenza Inverter/PCS: %.0f kW\n', invPower_kW(bestIdx));
fprintf('  - Capacità Batteria: %.2f kWh\n', BESS_min(bestIdx));

% CAPEX nuovo modello per best config
P_PV_best_kWp = (nModules(bestIdx) * Pmod_Wp) / 1000;
eco_best_S1 = computeEconomics(P_PV_best_kWp, BESS_min(bestIdx), invPower_kW(bestIdx), CONS_1Y, DMR, YEAR, cost);
best_CAPEX_S1 = eco_best_S1.CAPEX_total;

% Chiama Simulazione_Eco (come prima)
Simulazione_Eco(nModules(bestIdx), invPower_kW(bestIdx), BESS_min(bestIdx), SAVINGS_Y1(bestIdx), best_CAPEX_S1, ...
                'Scenario 1: BESS Ottimale', [], 1);

%% ========================================================================
%  9.1) GRAFICO PRODUZIONE vs DOMANDA + SOC - CONFIGURAZIONE MIGLIORE (SCENARIO 1)
%  ========================================================================
bestFile_S1 = fullfile(pvFolder, pvFiles(find(allModules == nModules(bestIdx) & allTilts == tilt(bestIdx), 1)).name);
TTpv_best_S1 = readPVsystHourlyCSV(bestFile_S1);
pv_kWh_best_S1 = TTpv_best_S1.E_kWh;

[~, SOC_history_S1] = findMinBatteryCapacity(load_kWh, pv_kWh_best_S1, BATT_EFF, SOC_MIN, SOC_MAX);

figure('Position', [100 100 1400 900], 'Color', 'w');
time_days = (1:8760) / 24;

subplot(2,1,1); hold on;
plot(time_days, load_kWh, 'r-', 'LineWidth', 1, 'DisplayName', 'Domanda (Consumi)');
plot(time_days, pv_kWh_best_S1, 'b-', 'LineWidth', 1, 'DisplayName', 'Produzione PV');
grid on;
xlabel('Giorno dell''anno', 'FontSize', 11, 'FontWeight', 'bold');
ylabel('Energia [kWh]', 'FontSize', 11, 'FontWeight', 'bold');
title('Produzione PV vs Domanda - Configurazione Migliore (Scenario 1)', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best');
xlim([0 365]);

months_S1 = {'Gen', 'Feb', 'Mar', 'Apr', 'Mag', 'Giu', 'Lug', 'Ago', 'Set', 'Ott', 'Nov', 'Dic'};
days_in_month_S1 = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
cumdays_S1 = [0 cumsum(days_in_month_S1)];
xticks(cumdays_S1(1:12) + days_in_month_S1/2);
xticklabels(months_S1);

subplot(2,1,2);
plot(time_days, SOC_history_S1, 'g-', 'LineWidth', 1.5); hold on;
yline(SOC_MIN * 100, 'r--', 'LineWidth', 1.5, 'Label', sprintf('SOC min (%.0f%%)', SOC_MIN*100));
yline(SOC_MAX * 100, 'r--', 'LineWidth', 1.5, 'Label', sprintf('SOC max (%.0f%%)', SOC_MAX*100));
grid on;
xlabel('Giorno dell''anno', 'FontSize', 11, 'FontWeight', 'bold');
ylabel('State of Charge [%]', 'FontSize', 11, 'FontWeight', 'bold');
title(sprintf('Stato di Carica Batteria (BESS Ottimale: %.1f kWh)', BESS_min(bestIdx)), 'FontSize', 12, 'FontWeight', 'bold');
xlim([0 365]); ylim([0 100]);
xticks(cumdays_S1(1:12) + days_in_month_S1/2);
xticklabels(months_S1);
legend('SOC', sprintf('SOC min (%.0f%%)', SOC_MIN*100), sprintf('SOC max (%.0f%%)', SOC_MAX*100), 'Location', 'best');

sgtitle(sprintf('Scenario 1: %d Moduli, %d° Inclinazione, %.0f kW PCS, %.1f kWh BESS', ...
    nModules(bestIdx), tilt(bestIdx), invPower_kW(bestIdx), BESS_min(bestIdx)), 'FontSize', 14, 'FontWeight', 'bold');

%% ========================================================================
%  10) SCENARIO 2: BESS FISSA 200 kWh
%  ========================================================================
BESS_FIXED = 200;

fprintf('\n\n╔════════════════════════════════════════════════════════════╗\n');
fprintf('║       SCENARIO 2: BESS FISSA (200 kWh)                        ║\n');
fprintf('╚════════════════════════════════════════════════════════════╝\n');
fprintf('Configurazione selezionata: %s\n', cfgNames(bestIdx));
fprintf('  - Moduli: %d\n', nModules(bestIdx));
fprintf('  - Inclinazione: %d°\n', tilt(bestIdx));
fprintf('  - Potenza Inverter/PCS: %.0f kW\n', invPower_kW(bestIdx));
fprintf('  - Capacità Batteria: %.2f kWh (FISSA)\n', BESS_FIXED);

% CAPEX nuovo modello per Scenario 2
eco_best_S2 = computeEconomics(P_PV_best_kWp, BESS_FIXED, invPower_kW(bestIdx), CONS_1Y, DMR, YEAR, cost);
best_CAPEX_S2 = eco_best_S2.CAPEX_total;

% Rileggi PV best
bestFile = fullfile(pvFolder, pvFiles(find(allModules == nModules(bestIdx) & allTilts == tilt(bestIdx), 1)).name);
TTpv_best = readPVsystHourlyCSV(bestFile);
pv_kWh_best = TTpv_best.E_kWh;

% Simula batteria 200 kWh
[unmet_S2, SOC_history_S2, excess_S2, hourly_data_S2] = simulateBattery(load_kWh, pv_kWh_best, BESS_FIXED, BATT_EFF, SOC_MIN, SOC_MAX);

energia_autoconsumata = CONS_1Y - unmet_S2;
costo_acquisto_rete = unmet_S2 * COST_EL;
ricavi_vendita = excess_S2 * PREZZO_VENDITA;

% Savings netti (come tuo)
savings_S2 = energia_autoconsumata * COST_EL + ricavi_vendita;

fprintf('  - Energia autoconsumata: %.2f kWh/anno\n', energia_autoconsumata);
fprintf('  - Unmet Load (acquisto rete): %.2f kWh/anno\n', unmet_S2);
fprintf('  - Costo energia dalla rete: %.2f €/anno\n', costo_acquisto_rete);
fprintf('  - Energia venduta alla rete: %.2f kWh/anno\n', excess_S2);
fprintf('  - Ricavi vendita (@ %.2f €/kWh): %.2f €/anno\n', PREZZO_VENDITA, ricavi_vendita);
fprintf('  - Savings netti: %.2f €/anno\n', savings_S2);

Simulazione_Eco(nModules(bestIdx), invPower_kW(bestIdx), BESS_FIXED, savings_S2, best_CAPEX_S2, ...
                'Scenario 2: BESS 200 kWh', [], 2);

%% ========================================================================
%  12) SCENARIO 3: BESS 200 kWh + FINANZIAMENTO BANCARIO
%  ========================================================================
fprintf('\n');
fprintf('╔═══════════════════════════════════════════════════════════════════════════╗\n');
fprintf('║          SCENARIO 3: BESS 200 kWh + FINANZIAMENTO BANCARIO               ║\n');
fprintf('╠═══════════════════════════════════════════════════════════════════════════╣\n');
fprintf('║  Stesso setup tecnico dello Scenario 2, ma il CAPEX è finanziato con     ║\n');
fprintf('║  un prestito bancario al 4%% di interesse, rimborsato in 25 anni          ║\n');
fprintf('╚═══════════════════════════════════════════════════════════════════════════╝\n');

loanParams_S3.enabled = true;
loanParams_S3.rate  = 0.04;
loanParams_S3.years = 25;

loan_rate = loanParams_S3.rate;
loan_years = loanParams_S3.years;
loan_payment_preview = best_CAPEX_S2 * (loan_rate * (1 + loan_rate)^loan_years) / ((1 + loan_rate)^loan_years - 1);

fprintf('\n📊 DETTAGLI FINANZIAMENTO:\n');
fprintf('   Capitale finanziato:     %10.2f €\n', best_CAPEX_S2);
fprintf('   Tasso interesse:         %10.2f %%\n', loan_rate * 100);
fprintf('   Durata prestito:         %10d anni\n', loan_years);
fprintf('   Rata annuale costante:   %10.2f €/anno\n', loan_payment_preview);
fprintf('   Totale da rimborsare:    %10.2f €\n', loan_payment_preview * loan_years);
fprintf('   Interessi totali:        %10.2f €\n', loan_payment_preview * loan_years - best_CAPEX_S2);

Simulazione_Eco(nModules(bestIdx), invPower_kW(bestIdx), BESS_FIXED, ...
                savings_S2, best_CAPEX_S2, 'Scenario 3: BESS 200 kWh + Prestito Bancario', loanParams_S3, 2);

%% ========================================================================
%  FUNZIONI LOCALI
%  ========================================================================

function eco = computeEconomics(P_PV_kWp, E_BESS_kWh, P_PCS_kW, E_served_y, r, N_years, cost)
% Calcola CAPEX (breakdown), OPEX annuo, replacement annuo e LCOE = NPV(costs)/NPV(energy)
%
% Convenzione:
% - CAPEX al tempo 0
% - OPEX e replacement a fine di ogni anno (t=1..N_years)
% - LCOE = [CAPEX + sum((OPEX+repl)/df)] / [sum(E_served/df)]

    % --- CAPEX breakdown ---
    capex.PV   = P_PV_kWp   * cost.C_PV_EUR_per_kWp;
    capex.BESS = E_BESS_kWh * cost.C_BESS_EUR_per_kWh;

    if cost.include_PCS_in_BESS
        capex.PCS = 0;
    else
        capex.PCS = P_PCS_kW * cost.C_PCS_EUR_per_kW;
    end

    capex.fixed = cost.engineering_and_permitting_EUR + ...
                  cost.main_switchboard_and_grounding_EUR + ...
                  cost.monitoring_EUR + ...
                  cost.logistics_site_safety_EUR;

    capex.subtotal    = capex.PV + capex.BESS + capex.PCS + capex.fixed;
    capex.contingency = capex.subtotal * cost.contingency_rate;

    CAPEX_total = capex.subtotal + capex.contingency;

    % --- OPEX series ---
    OPEX_y = (capex.PV * cost.OPEX_PV_rate) + ...
             (capex.BESS * cost.OPEX_BESS_rate) + ...
             (CAPEX_total * cost.insurance_rate);

    OPEX_series = repmat(OPEX_y, N_years, 1);

    % --- Replacement series ---
    repl = zeros(N_years, 1);

    if cost.bess_life_years > 0
        yrs = cost.bess_life_years:cost.bess_life_years:N_years;
        repl(yrs) = repl(yrs) + capex.BESS * cost.bess_replacement_fraction;
    end

    if cost.pcs_life_years > 0
        yrs = cost.pcs_life_years:cost.pcs_life_years:N_years;

        if capex.PCS > 0
            pcs_base = capex.PCS;
        else
            pcs_base = P_PCS_kW * cost.pcs_equivalent_CAPEX_EUR_per_kW;
        end

        repl(yrs) = repl(yrs) + pcs_base * cost.pcs_replacement_fraction;
    end

    % --- Discount factors ---
    if r == 0
        df = ones(N_years, 1);
    else
        df = (1 + r).^((1:N_years)');
    end

    % --- NPV costs / energy -> LCOE ---
    NPV_costs  = CAPEX_total + sum((OPEX_series + repl) ./ df);
    NPV_energy = sum(repmat(E_served_y, N_years, 1) ./ df);

    LCOE = NPV_costs / NPV_energy;

    eco = struct();
    eco.CAPEX_total = CAPEX_total;
    eco.CAPEX_breakdown = capex;
    eco.OPEX_series = OPEX_series;
    eco.replacement_series = repl;
    eco.NPV_costs = NPV_costs;
    eco.NPV_energy = NPV_energy;
    eco.LCOE = LCOE;
end

function [unmet_total, SOC_history, excess_total, hourly_data] = simulateBattery(load_kWh, pv_kWh, BESS_cap, eff, SOC_min, SOC_max)
% Simula batteria ora per ora

    n = numel(load_kWh);

    cap_usable = BESS_cap * (SOC_max - SOC_min);
    SOC = cap_usable / 2;
    SOC_history = zeros(n, 1);

    hourly_data.autoconsumo  = zeros(n, 1);
    hourly_data.charging     = zeros(n, 1);
    hourly_data.from_battery = zeros(n, 1);
    hourly_data.buying       = zeros(n, 1);
    hourly_data.selling      = zeros(n, 1);

    unmet_total = 0;
    excess_total = 0;

    for t = 1:n
        net_power = pv_kWh(t) - load_kWh(t);

        if net_power >= 0
            hourly_data.autoconsumo(t) = load_kWh(t);
            surplus = net_power;

            energy_to_charge = min(surplus * eff, cap_usable - SOC);
            SOC = SOC + energy_to_charge;
            hourly_data.charging(t) = energy_to_charge / eff;

            energy_not_stored = surplus - (energy_to_charge / eff);
            hourly_data.selling(t) = max(energy_not_stored, 0);
            excess_total = excess_total + hourly_data.selling(t);
        else
            hourly_data.autoconsumo(t) = pv_kWh(t);
            energy_needed = -net_power;

            energy_from_battery = min(energy_needed / eff, SOC);
            SOC = SOC - energy_from_battery;

            energy_delivered = energy_from_battery * eff;
            hourly_data.from_battery(t) = energy_delivered;

            unmet = energy_needed - energy_delivered;
            hourly_data.buying(t) = max(unmet, 0);
            unmet_total = unmet_total + hourly_data.buying(t);
        end

        SOC_percent = SOC_min * 100 + (SOC / cap_usable) * (SOC_max - SOC_min) * 100;
        SOC_history(t) = SOC_percent;
    end
end
