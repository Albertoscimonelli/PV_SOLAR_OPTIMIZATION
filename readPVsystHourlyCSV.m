function TT = readPVsystHourlyCSV(csvPath, powerVarName)
% Robust reader for PVsyst hourly CSV (semicolon-separated)
% Looks for "data;E_Grid" header and then parses lines "dd/MM/yy HH:mm;<value>"
%
% Output:
%   TT - timetable with P_kW and E_kWh columns

    if nargin < 2 || strlength(powerVarName) == 0
        powerVarName = "E_Grid";
    end

    lines = readlines(csvPath);

    % --- find header row containing "data" and powerVarName ---
    headerRow = [];
    for i = 1:numel(lines)
        s = lower(strtrim(lines(i)));
        if contains(s, "data") && contains(s, lower(powerVarName))
            headerRow = i;
            break;
        end
    end
    assert(~isempty(headerRow), "Non trovo la riga 'data;%s' in %s", powerVarName, csvPath);

    % data starts after header + units row
    dataStart = headerRow + 2;
    dataLines = lines(dataStart:end);

    % --- parse lines with a counter (no mismatches possible) ---
    n = numel(dataLines);
    time = NaT(n,1);
    P_kW = nan(n,1);
    k = 0;

    for i = 1:n
        s = strtrim(dataLines(i));
        if strlength(s) == 0
            continue;
        end

        parts = split(s, ";");
        if numel(parts) < 2
            continue;
        end

        dtStr  = strtrim(parts(1));
        valStr = strtrim(parts(2));

        % parse datetime: assume yy is 1990 (PVsyst uses 2-digit year)
        try
            t = datetime(dtStr, "InputFormat", "dd/MM/yy HH:mm", "PivotYear", 1990);
        catch
            continue;
        end
        
        if isnat(t)
            continue;
        end

        % parse value (decimals are already with ".")
        v = str2double(valStr);
        if ~isfinite(v)
            continue;
        end

        k = k + 1;
        time(k) = t;
        P_kW(k) = v;
    end

    % trim to actual length
    time = time(1:k);
    P_kW = P_kW(1:k);

    assert(k > 0, "Parsing fallito: nessun dato valido estratto da %s", csvPath);

    % clamp small negatives from PVsyst
    P_kW = max(P_kW, 0);

    % hourly energy (1h timestep)
    E_kWh = P_kW * 1.0;

    TT = timetable(time, P_kW, E_kWh, 'VariableNames', {'P_kW','E_kWh'});

    if height(TT) ~= 8760
        warning("File %s: attese 8760 righe, trovate %d.", csvPath, height(TT));
    end
end
