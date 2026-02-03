function Simulazione_Eco(nModules, invPower_kW, bessCapacity_kWh, savings_Y1, CAPEX, scenarioName)
    % SIMULAZIONE_ECO Esegue l'analisi finanziaria dettagliata per una configurazione
    %
    % Input:
    %   nModules         - Numero di moduli PV
    %   invPower_kW      - Potenza inverter [kW]
    %   bessCapacity_kWh - Capacità batteria [kWh]
    %   savings_Y1       - Risparmio anno 1 [€]
    %   CAPEX            - Investimento iniziale totale [€]
    %   scenarioName     - (Opzionale) Nome dello scenario per i grafici
    %
    % Esempio di chiamata:
    %   Simulazione_Eco(440, 250, 1634.46, 22147.18, 285135.2, 'Scenario 1')
    
    % Parametro opzionale: nome scenario
    if nargin < 6 || isempty(scenarioName)
        scenarioName = 'Scenario';
    end
    
    %% 1. Parametri Economici
    YEARS = 25;           % Orizzonte temporale [anni]
    DMR = 0.04;           % Discount Market Rate (4%)
    TASSO_INF = 0.02;     % Tasso inflazione (2%)
    OPEX_RATE = 0.02;     % OPEX annuo come % del CAPEX (2%)
    COST_BATT = 120;      % Costo batteria [€/kWh]
    BATT_REPLACEMENT_YEAR = 15;  % Anno sostituzione batteria
    
    % Calcolo OPEX anno 1
    opex_Y1 = OPEX_RATE * CAPEX;
    
    % Costo sostituzione batteria (indicizzato all'inflazione all'anno 15)
    batt_replacement_cost = COST_BATT * bessCapacity_kWh * (1 + TASSO_INF)^(BATT_REPLACEMENT_YEAR-1);
    
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
    
    % Anno 0: Solo investimento iniziale
    cash_flow(1) = -CAPEX;
    discounted_cf(1) = -CAPEX;
    cumulative_npv(1) = -CAPEX;
    capex_arr(1) = -CAPEX;
    
    fprintf('\n--- ANALISI FLUSSI DI CASSA (%s) ---\n', scenarioName);
    fprintf('%-6s | %-12s | %-12s | %-14s | %-12s | %-12s\n', 'Anno', 'Savings', 'OPEX', 'Batt Repl.', 'Cash Flow', 'NPV Cumul.');
    fprintf('--------------------------------------------------------------------------------------------\n');
    fprintf('%-6d | %-12.2f | %-12.2f | %-14.2f | %-12.2f | %-12.2f\n', 0, 0, 0, 0, cash_flow(1), cumulative_npv(1));

    for t = 1:YEARS
        % Calcolo risparmi e opex indicizzati all'inflazione
        savings_t = savings_Y1 * (1 + TASSO_INF)^(t-1);
        opex_t = opex_Y1 * (1 + TASSO_INF)^(t-1);
        
        % Sostituzione batteria anno 15
        batt_repl_t = 0;
        if t == BATT_REPLACEMENT_YEAR
            batt_repl_t = batt_replacement_cost;
        end
        
        % Salva entrate e uscite separate
        savings_arr(t+1) = savings_t;
        opex_arr(t+1) = -opex_t;  % Negativo perché è un'uscita
        batt_repl_arr(t+1) = -batt_repl_t;  % Negativo perché è un'uscita
        
        % Flusso di cassa netto dell'anno t (inclusa sostituzione batteria)
        cash_flow(t+1) = savings_t - opex_t - batt_repl_t;
        
        % Attualizzazione al tempo zero (Discounting)
        discounted_cf(t+1) = cash_flow(t+1) / (1 + DMR)^t;
        
        % NPV Cumulativo
        cumulative_npv(t+1) = cumulative_npv(t) + discounted_cf(t+1);
        
        if t == BATT_REPLACEMENT_YEAR
            fprintf('%-6d | %-12.2f | %-12.2f | %-14.2f | %-12.2f | %-12.2f  <-- SOST. BATTERIA\n', t, savings_t, opex_t, batt_repl_t, cash_flow(t+1), cumulative_npv(t+1));
        else
            fprintf('%-6d | %-12.2f | %-12.2f | %-14.2f | %-12.2f | %-12.2f\n', t, savings_t, opex_t, batt_repl_t, cash_flow(t+1), cumulative_npv(t+1));
        end
    end

    %% 3. Visualizzazione Grafica
    figure('Position', [100, 100, 1200, 700], 'Color', 'w');
    
    % Grafico a barre raggruppate: Entrate vs Uscite
    subplot(2,1,1);
    
    % Prepara dati per barre raggruppate (inclusa sostituzione batteria)
    % Uscite totali = OPEX + Sostituzione batteria
    total_outflows = opex_arr(2:end)' + batt_repl_arr(2:end)';
    bar_data = [savings_arr(2:end)', total_outflows];
    b = bar(1:YEARS, bar_data, 'grouped');
    b(1).FaceColor = [0.2 0.7 0.3];  % Verde per Savings (entrate)
    b(2).FaceColor = [0.9 0.3 0.3];  % Rosso per Uscite (OPEX + Batt)
    
    hold on;
    % Linea del cash flow netto
    plot(1:YEARS, cash_flow(2:end), '-ok', 'LineWidth', 2, 'MarkerFaceColor', 'k', 'MarkerSize', 6);
    
    % Evidenzia anno sostituzione batteria con barra aggiuntiva
    if BATT_REPLACEMENT_YEAR <= YEARS
        bar(BATT_REPLACEMENT_YEAR, batt_repl_arr(BATT_REPLACEMENT_YEAR+1), 0.3, ...
            'FaceColor', [0.6 0.1 0.1], 'EdgeColor', 'k', 'LineWidth', 1.5);
        text(BATT_REPLACEMENT_YEAR, batt_repl_arr(BATT_REPLACEMENT_YEAR+1) - 5000, ...
            sprintf('Sost. Batt.\n%.0f €', -batt_repl_arr(BATT_REPLACEMENT_YEAR+1)), ...
            'HorizontalAlignment', 'center', 'FontSize', 8, 'FontWeight', 'bold', 'Color', [0.6 0.1 0.1]);
    end
    
    ylabel('Flusso [€]', 'FontSize', 11, 'FontWeight', 'bold');
    xlabel('Anno', 'FontSize', 11, 'FontWeight', 'bold');
    title('Flussi di Cassa Annuali: Entrate vs Uscite', 'FontSize', 12, 'FontWeight', 'bold');
    legend('Savings (Entrate)', 'Uscite (OPEX + Sost. Batt)', 'Cash Flow Netto', 'Location', 'best');
    grid on;
    xlim([0 YEARS+1]);
    
    % Aggiungi annotazione CAPEX anno 0
    text(0.5, -CAPEX/2, sprintf('CAPEX\n%.0f €', CAPEX), ...
        'HorizontalAlignment', 'center', 'FontSize', 9, 'FontWeight', 'bold', 'Color', 'red');
    
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
    fprintf('OPEX Anno 1:           %12.2f €/anno\n', opex_Y1);
    fprintf('Savings Anno 1:        %12.2f €/anno\n', savings_Y1);
    fprintf('Net Benefit Anno 1:    %12.2f €/anno\n', savings_Y1 - opex_Y1);
    fprintf('--------------------------------------------\n');
    fprintf('Sost. Batteria (Anno %d): %10.2f €\n', BATT_REPLACEMENT_YEAR, batt_replacement_cost);
    fprintf('--------------------------------------------\n');
    fprintf('NPV Finale (%d anni):  %12.2f €\n', YEARS, cumulative_npv(end));
    if ~isempty(payback_year)
        fprintf('Payback Period:        %12.1f anni\n', payback_exact);
    end
    fprintf('============================================\n');
end