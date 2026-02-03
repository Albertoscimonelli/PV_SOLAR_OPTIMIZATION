function [BESS_min, SOC_history] = findMinBatteryCapacity(load_kWh, pv_kWh, eff, SOC_min, SOC_max)
% Trova la capacità minima della batteria per azzerare unmet load
% 
% Input:
%   load_kWh - consumi orari [8760×1] in kWh
%   pv_kWh   - produzione PV oraria [8760×1] in kWh
%   eff      - efficienza batteria (carica/scarica)
%   SOC_min  - stato di carica minimo (es. 0.1 = 10%)
%   SOC_max  - stato di carica massimo (es. 0.9 = 90%)
%
% Output:
%   BESS_min - capacità nominale minima batteria [kWh]
%   SOC_history - storico SOC per ogni ora [8760×1] in kWh

    % Ricerca binaria per trovare capacità minima
    BESS_low = 0;      % Limite inferiore [kWh]
    BESS_high = 500;   % Limite superiore iniziale [kWh]
    tolerance = 0.1;   % Tolleranza [kWh]
    max_iter = 50;     % Max iterazioni
    
    % Prima trova un limite superiore valido
    [unmet, ~] = simulateBattery(load_kWh, pv_kWh, BESS_high, eff, SOC_min, SOC_max);
    while unmet > 1e-3 && BESS_high < 3000
        BESS_high = BESS_high * 2;
        [unmet, ~] = simulateBattery(load_kWh, pv_kWh, BESS_high, eff, SOC_min, SOC_max);
    end
    
    % Ricerca binaria vera e propria
    for iter = 1:max_iter
        BESS_mid = (BESS_low + BESS_high) / 2;
        [unmet, ~] = simulateBattery(load_kWh, pv_kWh, BESS_mid, eff, SOC_min, SOC_max);
        
        if BESS_high - BESS_low < tolerance
            break;  % Convergenza raggiunta
        end
        
        if unmet < 1e-3  % Capacità sufficiente
            BESS_high = BESS_mid;  % Prova con meno capacità
        else  % Capacità insufficiente
            BESS_low = BESS_mid;   % Serve più capacità
        end
    end
    
    BESS_min = BESS_high;  % Usa il limite superiore (soluzione sicura)
    
    % Ricalcola l'ultima simulazione per avere SOC_history finale
    [~, SOC_history] = simulateBattery(load_kWh, pv_kWh, BESS_min, eff, SOC_min, SOC_max);
end


function [unmet_total, SOC_history] = simulateBattery(load_kWh, pv_kWh, BESS_cap, eff, SOC_min, SOC_max)
% Simula batteria ora per ora
%
% Output:
%   unmet_total - energia totale non coperta [kWh]
%   SOC_history - storico SOC [8760×1] in percentuale (0-100%)

    n = numel(load_kWh);
    
    % Capacità utilizzabile [kWh]
    cap_usable = BESS_cap * (SOC_max - SOC_min);
    
    % Stato batteria [kWh] - inizia a metà della finestra utilizzabile
    SOC = cap_usable / 2;  
    SOC_history = zeros(n, 1);
    
    unmet_total = 0;
    
    for t = 1:n
        net_power = pv_kWh(t) - load_kWh(t);  % Bilancio orario
        
        if net_power > 0
            % Surplus: carica batteria (perdite in carica)
            energy_to_charge = min(net_power * eff, cap_usable - SOC);
            SOC = SOC + energy_to_charge;
            
        else
            % Deficit: scarica batteria (perdite in scarica)
            energy_needed = -net_power;
            energy_from_battery = min(energy_needed / eff, SOC);
            SOC = SOC - energy_from_battery;
            
            % Energia fornita effettivamente (con perdite)
            energy_delivered = energy_from_battery * eff;
            
            % Energia non coperta
            unmet = energy_needed - energy_delivered;
            unmet_total = unmet_total + max(unmet, 0);
        end
        
        % Converti SOC in percentuale della capacità totale
        % SOC varia da 0 a cap_usable, che corrisponde a SOC_min% - SOC_max% della capacità totale
        SOC_percent = SOC_min * 100 + (SOC / cap_usable) * (SOC_max - SOC_min) * 100;
        SOC_history(t) = SOC_percent;
    end
end