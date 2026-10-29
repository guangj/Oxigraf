    % Oxygraf Analyzer Real-Time GUI & Logger
    % 
    % By Guang Jin
    %  10-2-2026

function Oxygraf_GUI()
    
    % --- Shared Variables (Scope for all nested functions) ---
    device = [];
    fid = -1;
    isRecording = false; % Flag to track recording status
    startTime = datetime('now');
    plotCounter = 0;
    
    % --- Create Main UI Figure ---
    fig = uifigure('Name', 'Oxygraf Analyzer Interface', 'Position', [100, 100, 950, 620]);
    fig.CloseRequestFcn = @closeGUI; % Catch figure close event
    
    % --- Left Panel: Controls & Parameters ---
    pnl = uipanel(fig, 'Title', 'Control Panel', 'Position', [20, 20, 260, 580]);
    
    % 1. COM Port
    uilabel(pnl, 'Position', [15, 520, 90, 22], 'Text', 'COM Port:');
    portEdit = uieditfield(pnl, 'text', 'Position', [105, 520, 135, 22], 'Value', 'COM5');
    
    % 2. Baud Rate
    uilabel(pnl, 'Position', [15, 482, 90, 22], 'Text', 'Baud Rate:');
    baudDrop = uidropdown(pnl, 'Position', [105, 482, 135, 22], ...
        'Items', {'9600', '19200', '38400', '57600', '115200'}, 'Value', '9600');
    
    % 3. Filter
    uilabel(pnl, 'Position', [15, 444, 90, 22], 'Text', 'Filter:');
    filterItems = {'No filter (0)', '20ms avg (1)', '40ms avg (2)', '80ms avg (3)', ...
                   '160ms avg (4)', '200ms exp (5)', '300ms exp (6)', '500ms exp (7)', ...
                   '1s exp (8)', '2s exp (9)', '4s exp (10)', '8s exp (11)', '16s exp (12)'};
    filterData = 0:12; 
    filterDrop = uidropdown(pnl, 'Position', [105, 444, 135, 22], ...
        'Items', filterItems, 'ItemsData', filterData, 'Value', 1);
    
    % 4. Report Period
    uilabel(pnl, 'Position', [15, 406, 90, 22], 'Text', 'Report Period:');
    periodItems = {'On demand (0)', '9.2 ms (1)', '20 ms (2)', '50 ms (5)', ...
                   '100 ms (10)', '200 ms (20)', '500 ms (50)', '1 sec (100)'};
    periodData = [0, 1, 2, 5, 10, 20, 50, 100]; 
    periodDrop = uidropdown(pnl, 'Position', [105, 406, 135, 22], ...
        'Items', periodItems, 'ItemsData', periodData, 'Value', 2);
    
    % 5. File Name
    uilabel(pnl, 'Position', [15, 368, 90, 22], 'Text', 'File Name:');
    defaultFile = sprintf('Oxygraf_%s.csv', datestr(now, 'yyyymmdd_HHMMSS'));
    fileEdit = uieditfield(pnl, 'text', 'Position', [15, 343, 225, 22], 'Value', defaultFile);
    
    % 6. Control Buttons (Connect & Disconnect)
    connectBtn = uibutton(pnl, 'push', 'Position', [15, 295, 105, 35], 'Text', 'Connect', ...
        'BackgroundColor', [0.47 0.87 0.47], 'FontWeight', 'bold', 'ButtonPushedFcn', @connectAcquisition);
    
    disconnectBtn = uibutton(pnl, 'push', 'Position', [135, 295, 105, 35], 'Text', 'Disconnect', ...
        'BackgroundColor', [0.8 0.8 0.8], 'FontWeight', 'bold', 'Enable', 'off', 'ButtonPushedFcn', @disconnectAcquisition);
    
    % 7. Record Button (Toggle recording state)
    recordBtn = uibutton(pnl, 'push', 'Position', [15, 250, 225, 35], 'Text', 'Start Recording to CSV', ...
        'BackgroundColor', [0.3 0.6 0.9], 'FontColor', 'white', 'FontWeight', 'bold', 'Enable', 'off', 'ButtonPushedFcn', @toggleRecording);
    
    % 8. Status Label
    statusLbl = uilabel(pnl, 'Position', [15, 185, 225, 55], 'Text', 'Status: Disconnected.', ...
        'FontWeight', 'bold', 'WordWrap', 'on');
    
    % 9. Raw Data Display Line 
    uilabel(pnl, 'Position', [15, 145, 225, 22], 'Text', 'Raw Data Stream:', 'FontWeight', 'bold');
    rawDataEdit = uieditfield(pnl, 'text', 'Position', [15, 115, 225, 28], ...
        'Value', 'No data...', 'Editable', 'off', 'BackgroundColor', [0.94 0.94 0.94]);
    
    % --- Right Panel: Real-Time Plots ---
    axO2 = uiaxes(fig, 'Position', [300, 330, 630, 250]);
    title(axO2, 'O2 Concentration (%)');
    xlabel(axO2, 'Time (s)'); ylabel(axO2, 'O2 %');
    grid(axO2, 'on');
    lineO2 = animatedline(axO2, 'Color', '#0072BD', 'LineWidth', 1.5);
    %axO2.YLim = [0 100];
    
    axCO2 = uiaxes(fig, 'Position', [300, 40, 630, 250]);
    title(axCO2, 'CO2 Concentration (%)');
    xlabel(axCO2, 'Time (s)'); ylabel(axCO2, 'CO2 %');
    grid(axCO2, 'on');
    lineCO2 = animatedline(axCO2, 'Color', '#D95319', 'LineWidth', 1.5);
    %axCO2.YLim = [0 10];

    % =========================================================================
    % --- Callback Functions ---
    % =========================================================================

    % --- 1. Connect to COM Port and Show Waveform ---
    function connectAcquisition(~, ~)
        try
            port = portEdit.Value;
            baud = str2double(baudDrop.Value);
            
            statusLbl.Text = 'Status: Connecting to Oxygraf...';
            rawDataEdit.Value = 'Waiting for data...';
            drawnow;
            
            % Open Serial Port
            device = serialport(port, baud, 'Parity', 'none', 'DataBits', 8, 'StopBits', 1);
            
            % Send Configuration Commands
            f_val = filterDrop.Value;
            p_val = periodDrop.Value;
            
            write(device, [0x1b 'F 0;'], 'uint8'); pause(0.05);                     % ASCII output
            write(device, [0x1b sprintf('A %d;', f_val)], 'uint8'); pause(0.05);    % Filter setting
            write(device, [0x1b sprintf('P %d;', p_val)], 'uint8'); pause(0.05);    % Report period
            
            configureTerminator(device, "CR/LF");
            flush(device);
            
            % Start Data Transmission
            write(device, [0x1b 'R5,1,7,8,9,4;'], 'uint8');
            
            % Reset plots and timers
            clearpoints(lineO2);
            clearpoints(lineCO2);
            startTime = datetime('now');
            plotCounter = 0;
            
            % Enable asynchronous background reading via Callback
            configureCallback(device, "terminator", @serialReadCallback);
            
            % Update UI States
            connectBtn.Enable = 'off';
            disconnectBtn.Enable = 'on';
            disconnectBtn.BackgroundColor = [0.87 0.47 0.47];
            recordBtn.Enable = 'on';
            portEdit.Enable = 'off';
            baudDrop.Enable = 'off';
            filterDrop.Enable = 'off';
            periodDrop.Enable = 'off';
            
            statusLbl.Text = 'Status: Connected. Monitoring waveforms.';
            
        catch ME
            disconnectAcquisition();
            uialert(fig, sprintf('Failed to connect:\n%s', ME.message), 'Connection Error');
        end
    end

    % --- 2. Toggle CSV Recording State ---
    function toggleRecording(~, ~)
        if ~isRecording
            % START RECORDING
            filename = fileEdit.Value;
            fid = fopen(filename, 'w');
            if fid == -1
                uialert(fig, 'Cannot create file. Check permissions or path.', 'File Error');
                return;
            end
            % Write CSV Header
            fprintf(fid, 'PC_Time,Oxy_Timestamp,O2_Pct,CO2_Pct,CO2_Pressure,CO2_Temp,Flow_Rate\n');
            
            isRecording = true;
            
            % Update UI for recording mode
            recordBtn.Text = 'Stop Recording';
            recordBtn.BackgroundColor = [0.87 0.47 0.47]; % Red
            fileEdit.Enable = 'off';
            statusLbl.Text = sprintf('Status: Connected & RECORDING.\nFile: %s', filename);
            
        else
            % STOP RECORDING
            isRecording = false;
            if fid ~= -1
                fclose(fid);
                fid = -1;
            end
            
            % Update UI for monitoring mode
            recordBtn.Text = 'Start Recording to CSV';
            recordBtn.BackgroundColor = [0.3 0.6 0.9]; % Blue
            fileEdit.Enable = 'on';
            
            % Generate new default filename for next recording
            fileEdit.Value = sprintf('Oxygraf_%s.csv', datestr(now, 'yyyymmdd_HHMMSS'));
            statusLbl.Text = 'Status: Connected. Monitoring waveforms. (Data saved)';
        end
    end

    % --- 3. Serial Port Background Read Callback ---
    function serialReadCallback(src, ~)
        try
            % Read data up to terminator
            rawData = readline(src);
            cleanStr = strtrim(rawData);
            
            % Remove "R:" prefix
            cleanStr = regexprep(cleanStr, '^R:\s*', '');
            
            if isempty(cleanStr)
                return; 
            end
            
            % 1) Log to CSV (ONLY if Recording is active)
            if isRecording && fid ~= -1
                pcTime = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));
                fprintf(fid, '%s,%s\n', pcTime, cleanStr);
            end
            
            % 2) Parse for real-time plotting
            dataVals = str2double(split(cleanStr, ','));
            if length(dataVals) >= 3 % Need at least Timestamp, O2, CO2
                o2_val = dataVals(2);
                co2_val = dataVals(3);
                
                % Check if valid numbers
                if ~isnan(o2_val) && ~isnan(co2_val)
                    t_elapsed = seconds(datetime('now') - startTime);
                    
                    % Add points to lines
                    addpoints(lineO2, t_elapsed, o2_val/100);
                    addpoints(lineCO2, t_elapsed, co2_val/100);
                    
                    % Update plot & raw data display periodically to prevent GUI freezing
                    plotCounter = plotCounter + 1;
                    if mod(plotCounter, 5) == 0
                        % Display latest raw string in GUI text field
                        rawDataEdit.Value = cleanStr;
                        
                        % Auto-scroll X-Axis to show last 30 seconds
                        axO2.XLim = [max(0, t_elapsed - 30), max(30, t_elapsed)];
                        axCO2.XLim = [max(0, t_elapsed - 30), max(30, t_elapsed)];
                        drawnow limitrate;
                    end
                end
            end
        catch
            % Silently catch parsing errors for corrupted serial lines
        end
    end

    % --- 4. Disconnect from COM Port ---
    function disconnectAcquisition(~, ~)
        statusLbl.Text = 'Status: Disconnecting...';
        drawnow;
        
        % If currently recording, stop recording first
        if isRecording
            toggleRecording();
        end
        
        % Disable callback and delete device
        if ~isempty(device) && isvalid(device)
            configureCallback(device, "off");
            delete(device);
            device = [];
        end
        
        % Reset UI States (Unlock inputs)
        connectBtn.Enable = 'on';
        disconnectBtn.Enable = 'off';
        disconnectBtn.BackgroundColor = [0.8 0.8 0.8];
        recordBtn.Enable = 'off';
        recordBtn.Text = 'Start Recording to CSV';
        recordBtn.BackgroundColor = [0.3 0.6 0.9];
        
        portEdit.Enable = 'on';
        baudDrop.Enable = 'on';
        filterDrop.Enable = 'on';
        periodDrop.Enable = 'on';
        fileEdit.Enable = 'on';
        
        rawDataEdit.Value = 'Disconnected.';
        statusLbl.Text = 'Status: Disconnected.';
    end

    % --- 5. Clean up on Window Close ---
    function closeGUI(~, ~)
        disconnectAcquisition();
        delete(fig);
    end

end