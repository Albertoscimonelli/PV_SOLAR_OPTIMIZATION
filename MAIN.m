%% MAIN.m
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
COST_PV = 70;        % Costo pannelli fotovoltaici [€/modulo]
COST_INV = 150;      % Costo inverter [€/kW]
COST_BATT = 340;     % Costo batteria [€/kWh]
COST_EL = 0.2;       % Costo energia elettrica [€/kWh]
CONS_1Y = 73987;     % Consumo annuo [kWh]
OPEX_RATE = 0.03;    % OPEX annuo come % del CAPEX (3%)
TASSO_INF = 0.02;
DMR = 0.04;          % Discount Market Rate
YEAR = 20;           % Anni di simulazione

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
load_kWh = double(Tload{:, idxLoad});

% Verifica che ci siano esattamente 8760 ore (1 anno)
assert(numel(load_kWh) == 8760, "Consumi: attese 8760 righe, trovate %d", numel(load_kWh));
assert(all(isfinite(load_kWh)), "Consumi: trovati NaN/Inf.");

%% 2) RICERCA FILE PVSYST (CONFIGURAZIONI)
% Trova tutti i file CSV nella cartella PVsyst results
pvFiles = dir(fullfile(pvFolder, pvPattern));
assert(~isempty(pvFiles), "Nessun file PV trovato in %s", pvFolder);

nCfg = numel(pvFiles);  % Numero di configurazioni da confrontare

% Preallocazione array risultati
cfgNames   = strings(nCfg, 1);   % Nomi delle configurazioni
unmet_kWh  = zeros(nCfg, 1);     % Energia non coperta per ogni config
nModules   = zeros(nCfg, 1);     % Numero moduli per ogni config
invPower_kW = zeros(nCfg, 1);    % Potenza totale inverter [kW]
PV_prod_kWh = zeros(nCfg, 1);   % Energia prodotta annualmente [kWh]
SAVINGS_Y1 = zeros(nCfg, 1);     % Risparmio anno 1 [€]
OPEX       = zeros(nCfg, 1);     % Costi operativi annui [€/anno]
NPV        = zeros(nCfg, 1);     % Net Present Value [€]
LCOE       = zeros(nCfg, 1);     % Levelized Cost of Energy [€/kWh]

%% 3) LOOP SU TUTTE LE CONFIGURAZIONI
% Per ogni configurazione: calcola quanto il PV copre i consumi
for i = 1:nCfg
    fpath = fullfile(pvFiles(i).folder, pvFiles(i).name);
    
    fprintf('Processing %d/%d: %s\n', i, nCfg, pvFiles(i).name);
    
    % === LETTURA PRODUZIONE PV E CONFIG ===
    % Legge il file PVsyst e estrae solo la produzione oraria
    TTpv = readPVsystHourlyCSV(fpath);
    pv_kWh = TTpv.E_kWh;  % Energia prodotta ogni ora [kWh]
    
    fprintf('  -> Moduli: %d, Potenza inverter: %.1f kW\n', nModules(i), invPower_kW(i));
    
    % Verifica che anche il PV abbia 8760 ore
    assert(numel(pv_kWh) == 8760, "PV file %s: attese 8760 righe, trovate %d", pvFiles(i).name, numel(pv_kWh));
    
    % Calcola produzione annuale
    PV_prod_kWh(i) = sum(pv_kWh);
    
    % === CALCOLO DEFICIT ORARIO ===
    % deficit_kWh(t) = max(load(t) - pv(t), 0)
    % - Se load > pv → deficit positivo (energia che manca)
    % - Se load <= pv → deficit = 0 (PV copre tutto)
    deficit_kWh = max(load_kWh - pv_kWh, 0);
    
    % === SOMMA DEFICIT ANNUALE ===
    % Totale kWh non coperti dal PV in un anno
    unmet_kWh(i) = sum(deficit_kWh);
    
    % Salva il nome della configurazione (senza estensione)
    [~, name, ~] = fileparts(pvFiles(i).name);
    cfgNames(i) = string(name);
    
    %% 4.1 ) ECONOMIC PART
    IC(i)=COST_PV*nModules(i)+COST_INV*invPower_kW(i);

    SAVINGS_Y1(i)=Costo_annuo-unmet_kWh(i)*COST_EL;
    
    % OPEX = 3% del CAPEX annuo
    OPEX(i) = OPEX_RATE * IC(i);
    
    % LCOE con CAPEX annualizzato (Capital Recovery Factor)
    % CRF = [r * (1+r)^n] / [(1+r)^n - 1]
    CRF = (DMR * (1 + DMR)^YEAR) / ((1 + DMR)^YEAR - 1);
    CAPEX_annualizzato = IC(i) * CRF;
    LCOE(i) = (CAPEX_annualizzato + OPEX(i)) / PV_prod_kWh(i);
    
    % NPV considerando anche gli OPEX annuali
    % Net benefit annuale = SAVINGS - OPEX
    Net_benefit_Y1 = SAVINGS_Y1(i) - OPEX(i);
    NPV(i)=-IC(i)+Net_benefit_Y1*(1/(DMR-TASSO_INF))*(1-((1+TASSO_INF)/(1+DMR))^YEAR);

    % PRINT DEI RISULTATI PER CONTROLLO
    fprintf('  -> Unmet load: %.2f kWh\n', unmet_kWh(i));
    fprintf('  -> Investment Cost: %.2f €\n', IC(i));
    fprintf('  -> OPEX (annuo): %.2f €/y\n', OPEX(i));
    fprintf('  -> Savings Y1: %.2f €\n', SAVINGS_Y1(i));
    fprintf('  -> Net Benefit Y1: %.2f €/y\n', Net_benefit_Y1);
    fprintf('  -> LCOE: %.4f €/kWh\n', LCOE(i));
    fprintf('  -> NPV (20y): %.2f €\n', NPV(i));

end

%% 4) OUTPUT RISULTATI
% Crea tabella con tutti i dati
Results = table(cfgNames, nModules, invPower_kW, PV_prod_kWh, unmet_kWh, SAVINGS_Y1, OPEX, LCOE, NPV, ...
    'VariableNames', {'Config','N_Modules','InvPower_kW','PV_Production_kWh','UnmetLoad_kWh','Savings_EUR','OPEX_EUR','LCOE_EUR_kWh','NPV_EUR'});

% Ordina dal migliore NPV al peggiore
Results = sortrows(Results, 'NPV_EUR', 'descend');

% Stampa a schermo
fprintf('\n=== RISULTATI FINALI ===\n');
disp(Results);

% Salva su file CSV
writetable(Results, "results_unmet_load.csv");
fprintf('Salvato in: results_unmet_load.csv\n');
