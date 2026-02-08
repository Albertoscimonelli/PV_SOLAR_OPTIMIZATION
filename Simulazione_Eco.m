function Simulazione_Eco(nModules, invPower_kW, bessCapacity_kWh, savings_Y1, CAPEX, scenarioName, loanParams, nInverters, ecoParams)
    % SIMULAZIONE_ECO Esegue l'analisi finanziaria dettagliata per una configurazione
    %
    % Input:
    %   nModules         - Numero di moduli PV
    %   invPower_kW      - Potenza inverter [kW]
    %   bessCapacity_kWh - Capacità batteria [kWh]
    %   savings_Y1       - Risparmio anno 1 [€]
    %   CAPEX            - Investimento iniziale totale [€]
    %   scenarioName     - (Opzionale) Nome dello scenario per i grafici
    %   loanParams       - (Opzionale) Struct con parametri prestito:
    %                      .enabled  - true/false per attivare finanziamento
    %                      .rate     - tasso di interesse annuo (es. 0.04 = 4%)
    %                      .years    - durata del prestito in anni
    %   nInverters       - (Opzionale) Numero di inverter (default = 1)
    %   ecoParams        - (Opzionale) Struct con parametri economici:
    %                      .YEARS              - Orizzonte temporale [anni]
    %                      .DMR                - Discount Market Rate
    %                      .TASSO_INF          - Tasso inflazione
    %                      .OPEX_RATE          - OPEX annuo come % del CAPEX
    %                      .COST_BATT          - Costo batteria [€/kWh]
    %                      .COST_INV           - Costo inverter [€/kW]
    %                      .BATT_REPLACEMENT_YEAR - Anno sostituzione batteria
    %
    % Esempio di chiamata senza prestito:
    %   Simulazione_Eco(440, 250, 1634.46, 22147.18, 285135.2, 'Scenario 1')
    % Esempio con prestito e parametri custom:
    %   loan.enabled = true; loan.rate = 0.04; loan.years = 25;
    %   eco.YEARS = 25; eco.DMR = 0.04; eco.TASSO_INF = 0.03; eco.OPEX_RATE = 0.02;
    %   eco.COST_BATT = 130; eco.COST_INV = 50; eco.BATT_REPLACEMENT_YEAR = 15;
    %   Simulazione_Eco(440, 250, 200, 20000, 100000, 'Scenario 3', loan, 2, eco)
    
    % Parametro opzionale: nome scenario
    if nargin < 6 || isempty(scenarioName)
        scenarioName = 'Scenario';
    end
    
    % Parametro opzionale: prestito bancario
    if nargin < 7 || isempty(loanParams)
        loanParams.enabled = false;
    end
    
    % Parametro opzionale: numero di inverter (default = 1)
    if nargin < 8 || isempty(nInverters)
        nInverters = 1;
    end
    
    %% 1. Parametri Economici (da struct o default)
    if nargin < 9 || isempty(ecoParams)
        % Valori di default (backward compatibility)
        YEARS = 25;
        DMR = 0.04;
        TASSO_INF = 0.02;
        OPEX_RATE = 0.02;
        COST_BATT = 120;
        COST_INV = 50;
        BATT_REPLACEMENT_YEAR = 15;
    else
        % Usa parametri dalla struct (con fallback ai default se campo mancante)
        YEARS = getFieldOrDefault(ecoParams, 'YEARS', 25);
        DMR = getFieldOrDefault(ecoParams, 'DMR', 0.04);
        TASSO_INF = getFieldOrDefault(ecoParams, 'TASSO_INF', 0.02);
        OPEX_RATE = getFieldOrDefault(ecoParams, 'OPEX_RATE', 0.02);
        COST_BATT = getFieldOrDefault(ecoParams, 'COST_BATT', 120);
        COST_INV = getFieldOrDefault(ecoParams, 'COST_INV', 50);
        BATT_REPLACEMENT_YEAR = getFieldOrDefault(ecoParams, 'BATT_REPLACEMENT_YEAR', 15);
    end
    
    % Calcolo OPEX anno 1
    opex_Y1 = OPEX_RATE * CAPEX;
    
    % Costo sostituzione batteria + inverter (indicizzato all'inflazione all'anno 15)
    batt_replacement_cost = (COST_BATT * bessCapacity_kWh + COST_INV * invPower_kW * nInverters) * (1 + TASSO_INF)^(BATT_REPLACEMENT_YEAR-1);
    
    % === CALCOLO RATA PRESTITO (se abilitato) ===
    if loanParams.enabled
        loan_rate = loanParams.rate;
        loan_years = loanParams.years;
        % Formula rata costante (ammortamento francese)
        % Rata = Capitale * [r(1+r)^n] / [(1+r)^n - 1]
        loan_payment = CAPEX * (loan_rate * (1 + loan_rate)^loan_years) / ((1 + loan_rate)^loan_years - 1);
        fprintf('\n=== FINANZIAMENTO BANCARIO ===\n');
        fprintf('Capitale finanziato: %.2f €\n', CAPEX);
        fprintf('Tasso di interesse: %.2f%%\n', loan_rate * 100);
        fprintf('Durata prestito: %d anni\n', loan_years);
        fprintf('Rata annuale: %.2f €/anno\n', loan_payment);
        fprintf('Totale restituito: %.2f € (interessi: %.2f €)\n', loan_payment * loan_years, loan_payment * loan_years - CAPEX);
    else
        loan_payment = 0;
        loan_years = 0;
    end
    
    %% 2. Proiezione Flussi di Cassa Anno per Anno
    years = 0:YEARS;
    cash_flow = zeros(1, numel(years));
    discounted_cf = zeros(1, numel(years));
    cumulative_npv = zeros(1, numel(years));
    
    % Array per entrate e uscite separate
    savings_arr = zeros(1, numel(years));    % Entrate (risparmi)
    opex_arr = zeros(1, numel(years));       % Uscite (OPEX)
    capex_arr = zeros(1, numel(years));      % Uscite (CAPEX solo anno 0)
    batt_repl_arr = zeros(1, numel(years));  % Uscite (Sostituzione batteria anno 15)
    loan_arr = zeros(1, numel(years));       % Uscite (Rate prestito)
    
    % Anno 0: Investimento iniziale (0 se finanziato con prestito)
    if loanParams.enabled
        cash_flow(1) = 0;  % Nessun esborso iniziale (finanziato)
        discounted_cf(1) = 0;
        cumulative_npv(1) = 0;
        capex_arr(1) = 0;
    else
        cash_flow(1) = -CAPEX;
        discounted_cf(1) = -CAPEX;
        cumulative_npv(1) = -CAPEX;
        capex_arr(1) = -CAPEX;
    end
    
    fprintf('\n--- ANALISI FLUSSI DI CASSA (%s) ---\n', scenarioName);
    if loanParams.enabled
        fprintf('%-6s | %-12s | %-12s | %-12s | %-14s | %-12s | %-12s\n', 'Anno', 'Savings', 'OPEX', 'Rata Prest.', 'Batt Repl.', 'Cash Flow', 'NPV Cumul.');
        fprintf('--------------------------------------------------------------------------------------------------------------\n');
        fprintf('%-6d | %-12.2f | %-12.2f | %-12.2f | %-14.2f | %-12.2f | %-12.2f\n', 0, 0, 0, 0, 0, cash_flow(1), cumulative_npv(1));
    else
        fprintf('%-6s | %-12s | %-12s | %-14s | %-12s | %-12s\n', 'Anno', 'Savings', 'OPEX', 'Batt Repl.', 'Cash Flow', 'NPV Cumul.');
        fprintf('--------------------------------------------------------------------------------------------\n');
        fprintf('%-6d | %-12.2f | %-12.2f | %-14.2f | %-12.2f | %-12.2f\n', 0, 0, 0, 0, cash_flow(1), cumulative_npv(1));
    end

    for t = 1:YEARS
        % Calcolo risparmi e opex indicizzati all'inflazione
        savings_t = savings_Y1 * (1 + TASSO_INF)^(t-1);
        opex_t = opex_Y1 * (1 + TASSO_INF)^(t-1);
        
        % Rata prestito (se attivo e entro la durata)
        loan_t = 0;
        if loanParams.enabled && t <= loan_years
            loan_t = loan_payment;
        end
        
        % Sostituzione batteria anno 15
        batt_repl_t = 0;
        if t == BATT_REPLACEMENT_YEAR
            batt_repl_t = batt_replacement_cost;
        end
        
        % Salva entrate e uscite separate
        savings_arr(t+1) = savings_t;
        opex_arr(t+1) = -opex_t;  % Negativo perché è un'uscita
        batt_repl_arr(t+1) = -batt_repl_t;  % Negativo perché è un'uscita
        loan_arr(t+1) = -loan_t;  % Negativo perché è un'uscita
        
        % Flusso di cassa netto dell'anno t (inclusa sostituzione batteria e rata prestito)
        cash_flow(t+1) = savings_t - opex_t - batt_repl_t - loan_t;
        
        % Attualizzazione al tempo zero (Discounting)
        discounted_cf(t+1) = cash_flow(t+1) / (1 + DMR)^t;
        
        % NPV Cumulativo
        cumulative_npv(t+1) = cumulative_npv(t) + discounted_cf(t+1);
        
        % Stampa riga tabella
        if loanParams.enabled
            if t == BATT_REPLACEMENT_YEAR
                fprintf('%-6d | %-12.2f | %-12.2f | %-12.2f | %-14.2f | %-12.2f | %-12.2f  <-- SOST. BATTERIA\n', t, savings_t, opex_t, loan_t, batt_repl_t, cash_flow(t+1), cumulative_npv(t+1));
            else
                fprintf('%-6d | %-12.2f | %-12.2f | %-12.2f | %-14.2f | %-12.2f | %-12.2f\n', t, savings_t, opex_t, loan_t, batt_repl_t, cash_flow(t+1), cumulative_npv(t+1));
            end
        else
            if t == BATT_REPLACEMENT_YEAR
                fprintf('%-6d | %-12.2f | %-12.2f | %-14.2f | %-12.2f | %-12.2f  <-- SOST. BATTERIA\n', t, savings_t, opex_t, batt_repl_t, cash_flow(t+1), cumulative_npv(t+1));
            else
                fprintf('%-6d | %-12.2f | %-12.2f | %-14.2f | %-12.2f | %-12.2f\n', t, savings_t, opex_t, batt_repl_t, cash_flow(t+1), cumulative_npv(t+1));
            end
        end
    end

    %% 3. Visualizzazione Grafica
    figure('Position', [100, 100, 1200, 700], 'Color', 'w');
    
    % Grafico a barre raggruppate: Entrate vs Uscite
    subplot(2,1,1);
    
    % Prepara dati per barre raggruppate (inclusa sostituzione batteria e prestito)
    % Uscite totali = OPEX + Sostituzione batteria + Rata prestito
    total_outflows = opex_arr(2:end)' + batt_repl_arr(2:end)' + loan_arr(2:end)';
    bar_data = [savings_arr(2:end)', total_outflows];
    b = bar(1:YEARS, bar_data, 'grouped');
    b(1).FaceColor = [0.2 0.7 0.3];  % Verde per Savings (entrate)
    b(2).FaceColor = [0.9 0.3 0.3];  % Rosso per Uscite (OPEX + Batt)
    
    hold on;
    % Linea del cash flow netto
    plot(1:YEARS, cash_flow(2:end), '-ok', 'LineWidth', 2, 'MarkerFaceColor', 'k', 'MarkerSize', 6);
    
    ylabel('Flusso [€]', 'FontSize', 11, 'FontWeight', 'bold');
    xlabel('Anno', 'FontSize', 11, 'FontWeight', 'bold');
    title('Flussi di Cassa Annuali: Entrate vs Uscite', 'FontSize', 12, 'FontWeight', 'bold');
    
    % Legenda dinamica in base a scenario prestito
    if loanParams.enabled
        legend('Savings (Entrate)', 'Uscite (OPEX + Batt + Rata)', 'Cash Flow Netto', 'Location', 'best');
    else
        legend('Savings (Entrate)', 'Uscite (OPEX + Sost. Batt)', 'Cash Flow Netto', 'Location', 'best');
    end
    grid on;
    xlim([0 YEARS+1]);
    
    % Aggiungi annotazione CAPEX anno 0 (solo se non c'è prestito)
    if ~loanParams.enabled
        text(0.5, -CAPEX/2, sprintf('CAPEX\n%.0f €', CAPEX), ...
            'HorizontalAlignment', 'center', 'FontSize', 9, 'FontWeight', 'bold', 'Color', 'red');
    else
        % Annotazione per scenario con prestito
        text(0.5, mean(cash_flow(2:6)), sprintf('Finanziato\n100%%'), ...
            'HorizontalAlignment', 'center', 'FontSize', 9, 'FontWeight', 'bold', 'Color', 'blue');
    end
    
    % Subplot 2: NPV Cumulativo
    subplot(2,1,2);
    
    % Area colorata per NPV positivo/negativo
    hold on;
    area(years, max(cumulative_npv, 0), 'FaceColor', [0.7 0.9 0.7], 'EdgeColor', 'none', 'FaceAlpha', 0.5);
    area(years, min(cumulative_npv, 0), 'FaceColor', [0.9 0.7 0.7], 'EdgeColor', 'none', 'FaceAlpha', 0.5);
    
    plot(years, cumulative_npv, '-o', 'Color', [0.1 0.1 0.6], 'LineWidth', 2.5, 'MarkerSize', 5, 'MarkerFaceColor', [0.1 0.1 0.6]);
    yline(0, 'k--', 'LineWidth', 1.5);
    
    ylabel('NPV Cumulativo [€]', 'FontSize', 11, 'FontWeight', 'bold');
    xlabel('Anno', 'FontSize', 11, 'FontWeight', 'bold');
    title('NPV Cumulativo nel Tempo', 'FontSize', 12, 'FontWeight', 'bold');
    grid on;
    xlim([0 YEARS]);
    
    % Identificazione Break-even (Payback Period)
    payback_year = find(cumulative_npv > 0, 1) - 1;
    if ~isempty(payback_year)
        % Calcola payback più preciso con interpolazione lineare
        if payback_year > 0
            frac = -cumulative_npv(payback_year) / (cumulative_npv(payback_year+1) - cumulative_npv(payback_year));
            payback_exact = payback_year - 1 + frac;
        else
            payback_exact = payback_year;
        end
        xline(payback_exact, 'b--', sprintf('Payback: %.1f anni', payback_exact), ...
            'LineWidth', 2, 'LabelOrientation', 'horizontal', 'LabelVerticalAlignment', 'bottom');
        legend('NPV > 0', 'NPV < 0', 'NPV Cumulativo', 'Break-even', 'Payback', 'Location', 'southeast');
    else
        fprintf('\n⚠️  ATTENZIONE: Payback period non raggiunto in %d anni!\n', YEARS);
        legend('NPV > 0', 'NPV < 0', 'NPV Cumulativo', 'Break-even', 'Location', 'southeast');
    end
    
    % Titolo generale figura
    sgtitle(sprintf('%s - Analisi Economica %d Anni: %d Moduli, %d kW Inv, %.0f kWh BESS', ...
        scenarioName, YEARS, nModules, invPower_kW, bessCapacity_kWh), 'FontSize', 14, 'FontWeight', 'bold');
    
    %% 4. Stampa Riepilogo Finale
    fprintf('\n============================================\n');
    fprintf('   RIEPILOGO ANALISI ECONOMICA - %s   \n', scenarioName);
    fprintf('============================================\n');
    fprintf('CAPEX Totale:          %12.2f €\n', CAPEX);
    
    % Dettagli prestito se abilitato
    if loanParams.enabled
        total_interest = loan_payment * loanParams.years - CAPEX;
        fprintf('--------------------------------------------\n');
        fprintf('FINANZIAMENTO BANCARIO:\n');
        fprintf('  Tasso interesse:     %12.2f %%\n', loanParams.rate * 100);
        fprintf('  Durata prestito:     %12d anni\n', loanParams.years);
        fprintf('  Rata annuale:        %12.2f €/anno\n', loan_payment);
        fprintf('  Totale rate:         %12.2f €\n', loan_payment * loanParams.years);
        fprintf('  Interessi totali:    %12.2f €\n', total_interest);
        fprintf('--------------------------------------------\n');
    end
    
    fprintf('OPEX Anno 1:           %12.2f €/anno\n', opex_Y1);
    fprintf('Savings Anno 1:        %12.2f €/anno\n', savings_Y1);
    fprintf('Net Benefit Anno 1:    %12.2f €/anno\n', savings_Y1 - opex_Y1);
    if loanParams.enabled
        fprintf('Net Benefit (con rata):%12.2f €/anno\n', savings_Y1 - opex_Y1 - loan_payment);
    end
    fprintf('--------------------------------------------\n');
    fprintf('Sost. Batteria (Anno %d): %10.2f €\n', BATT_REPLACEMENT_YEAR, batt_replacement_cost);
    fprintf('--------------------------------------------\n');
    fprintf('NPV Finale (%d anni):  %12.2f €\n', YEARS, cumulative_npv(end));
    if ~isempty(payback_year)
        fprintf('Payback Period:        %12.1f anni\n', payback_exact);
    end
    fprintf('============================================\n');
end

%% Funzione helper per ottenere campo da struct con valore di default
function val = getFieldOrDefault(s, fieldName, defaultVal)
    if isfield(s, fieldName)
        val = s.(fieldName);
    else
        val = defaultVal;
    end
end