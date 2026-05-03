function SpikeSorterApp()
% SpikeSorterApp  Spike sorter UI with manual correction and ISI overview.
%
% New features vs previous version:
%   - ISI scatter panel above the trace (click a point to jump there)
%   - Arrow key panning in select mode (same x-zoom, step by window width)
%   - Noise group always present; spikes assignable to it
%   - Panel layout fixed so listboxes sit correctly inside their borders
%
% Workflow:
%   1. Enter NB, page, range → Load Experiment
%   2. Select nerve channel and file
%   3. Configure sort settings (method, spike filter)
%   4. Run Sort
%   5. Manual correction: Select Mode + click/drag to select, reassign to label
%   6. Rename / quick-assign whole groups
%   7. Step through files with Prev / Next or arrow keys
%   8. Export all sorted files for this channel to .mat

    %% ---- Shared state ------------------------------------------------
    state.experiment   = [];
    state.channel      = '';
    state.fileIdx      = 1;
    state.trace        = [];
    state.results      = struct();

    edit.active       = false;
    edit.selected     = [];
    edit.dragStart    = [];
    edit.isDragging   = false;

    undoStack = {};

    NERVE_CHANNELS = {'lvn','pdn','lpn','llvn','ulvn','pyn','mvn','lgn'};
    NOISE_GROUP    = 'noise';   % always-present default group
    Fs             = 1e4;

    GROUP_COLORS = lines(10);
    SEL_COLOR    = [1.0 0.85 0.0];
    NOISE_COLOR  = [0.6 0.6 0.6];   % grey for noise

    %% ---- Layout constants --------------------------------------------
    FIG_W  = 1280;
    FIG_H  = 820;
    LEFT_W = 155;   % channel list panel
    FILE_W = 170;   % file list panel
    RIGHT_W = 290;  % label + settings panels
    MID_X  = LEFT_W + FILE_W;
    MID_W  = FIG_W - MID_X - RIGHT_W;
    TOP_H  = 40;    % top bar
    CTRL_H = 200;   % controls below trace
    ISI_H  = 160;   % ISI panel height
    TRACE_H = FIG_H - TOP_H - CTRL_H - ISI_H;

    %% ---- Figure ------------------------------------------------------
    fig = uifigure('Name', 'SpikeSorter', ...
        'Position', [80 80 FIG_W FIG_H], ...
        'KeyPressFcn', @onKeyPress);

    % ----------------------------------------------------------------
    % Top bar
    % ----------------------------------------------------------------
    topPanel = uipanel(fig, ...
        'Position', [0 FIG_H-TOP_H FIG_W TOP_H], ...
        'BorderType', 'none', 'BackgroundColor', [0.94 0.94 0.94]);

    uilabel(topPanel, 'Text', 'NB:',   'Position', [10  10 25 20]);
    nbField = uieditfield(topPanel, 'numeric', ...
        'Value', 901, 'Position', [38 8 60 22], 'Limits', [1 9999]);

    uilabel(topPanel, 'Text', 'Page:', 'Position', [112 10 35 20]);
    pageField = uieditfield(topPanel, 'numeric', ...
        'Value', 80,  'Position', [150 8 60 22], 'Limits', [1 9999]);

    uilabel(topPanel, 'Text', 'Range:', 'Position', [224 10 42 20]);
    rangeDropdown = uidropdown(topPanel, ...
        'Items', {'all','roi','continuousRamp','crash'}, ...
        'Position', [269 8 130 22]);

    uibutton(topPanel, 'Text', 'Load Experiment', ...
        'Position', [414 6 130 26], ...
        'ButtonPushedFcn', @(~,~) onLoad());

    statusLabel = uilabel(topPanel, 'Text', 'Ready.', ...
        'Position', [560 10 680 20], 'FontColor', [0.35 0.35 0.35]);

    CONTENT_Y = 0;                  % y=0 at bottom, top bar sits at top
    CONTENT_H = FIG_H - TOP_H;     % height available below top bar

    % ----------------------------------------------------------------
    % Left: channel list (panel + listbox both at fig level)
    % ----------------------------------------------------------------
    uipanel(fig, 'Title', 'Channels', ...
        'Position', [0 CONTENT_Y LEFT_W CONTENT_H]);
    channelList = uilistbox(fig, 'Items', {}, ...
        'Position', [4 CONTENT_Y+20 LEFT_W-8 CONTENT_H-24], ...
        'ValueChangedFcn', @(src,~) onChannelSelected(src.Value));

    % ----------------------------------------------------------------
    % Centre-left: file list
    % ----------------------------------------------------------------
    uipanel(fig, 'Title', 'Files', ...
        'Position', [LEFT_W CONTENT_Y FILE_W CONTENT_H]);
    fileList = uilistbox(fig, 'Items', {}, ...
        'Position', [LEFT_W+4 CONTENT_Y+20 FILE_W-8 CONTENT_H-24], ...
        'ValueChangedFcn', @(src,~) onFileSelected(src.Value));

    % ----------------------------------------------------------------
    % ISI scatter panel (above trace)
    % ----------------------------------------------------------------
    ISI_Y = CTRL_H + TRACE_H;
    isiPanel = uipanel(fig, 'Title', 'ISI Overview  (click to jump)', ...
        'Position', [MID_X ISI_Y MID_W ISI_H]);
    isiAx = uiaxes(isiPanel, ...
        'Position', [8 8 MID_W-16 ISI_H-28]);
    isiAx.XLabel.String = 'Time (s)';
    isiAx.YLabel.String = 'ISI (s)';
    isiAx.YScale = 'log';
    disableDefaultInteractivity(isiAx);
    isiAx.Toolbar.Visible = 'off';
    isiAx.ButtonDownFcn = @onIsiClick;

    % ----------------------------------------------------------------
    % Trace panel
    % ----------------------------------------------------------------
    tracePanel = uipanel(fig, 'Title', 'Trace', ...
        'Position', [MID_X CTRL_H MID_W TRACE_H]);
    traceAx = uiaxes(tracePanel, ...
        'Position', [8 8 MID_W-16 TRACE_H-28]);
    traceAx.XLabel.String = 'Time (s)';
    traceAx.YLabel.String = 'mV';
    title(traceAx, 'Load an experiment to begin');
    traceAx.ButtonDownFcn     = @onAxesClick;
    fig.WindowButtonMotionFcn = @onMouseMove;
    fig.WindowButtonUpFcn     = @onMouseUp;

    % ----------------------------------------------------------------
    % Controls panel (below trace)
    % ----------------------------------------------------------------
    ctrlPanel = uipanel(fig, 'Position', [MID_X 0 MID_W CTRL_H], ...
        'BorderType', 'none');

    sortBtn = uibutton(ctrlPanel, 'Text', '▶  Sort This File', ...
        'Position', [8 168 138 26], 'Enable', 'off', ...
        'ButtonPushedFcn', @(~,~) onSort());
    sortAllBtn = uibutton(ctrlPanel, 'Text', 'Sort All Files', ...
        'Position', [154 168 118 26], 'Enable', 'off', ...
        'ButtonPushedFcn', @(~,~) onSortAll());
    prevBtn = uibutton(ctrlPanel, 'Text', '◀ Prev', ...
        'Position', [8 136 84 26], 'Enable', 'off', ...
        'ButtonPushedFcn', @(~,~) stepFile(-1));
    nextBtn = uibutton(ctrlPanel, 'Text', 'Next ▶', ...
        'Position', [100 136 84 26], 'Enable', 'off', ...
        'ButtonPushedFcn', @(~,~) stepFile(1));
    fileCountLabel = uilabel(ctrlPanel, 'Text', '', ...
        'Position', [196 140 160 18], 'FontColor', [0.4 0.4 0.4]);
    exportBtn = uibutton(ctrlPanel, 'Text', 'Export .mat', ...
        'Position', [MID_W-120 168 112 26], 'Enable', 'off', ...
        'ButtonPushedFcn', @(~,~) onExport());

    infoLabel = uilabel(ctrlPanel, 'Text', '', ...
        'Position', [8 108 MID_W-16 18], 'FontColor', [0.3 0.3 0.3]);
    progressLabel = uilabel(ctrlPanel, 'Text', '', ...
        'Position', [8 88 MID_W-16 18], 'FontColor', [0.2 0.5 0.2]);

    % Manual correction row
    uipanel(ctrlPanel, 'Title', 'Manual Correction', ...
        'Position', [0 0 MID_W-2 82]);
    selectBtn = uibutton(ctrlPanel, 'Text', '⊙  Select Mode: OFF', ...
        'Position', [8 50 158 24], 'Enable', 'off', ...
        'ButtonPushedFcn', @(~,~) toggleSelectMode());
    clearSelBtn = uibutton(ctrlPanel, 'Text', 'Clear Selection', ...
        'Position', [174 50 110 24], 'Enable', 'off', ...
        'ButtonPushedFcn', @(~,~) clearSelection());
    selCountLabel = uilabel(ctrlPanel, 'Text', '0 spikes selected', ...
        'Position', [292 54 160 18], 'FontColor', [0.5 0.3 0.0]);
    undoBtn = uibutton(ctrlPanel, 'Text', '↩  Undo', ...
        'Position', [MID_W-118 50 108 24], 'Enable', 'off', ...
        'ButtonPushedFcn', @(~,~) onUndo());
    uilabel(ctrlPanel, 'Text', 'Reassign selected →', ...
        'Position', [8 24 140 18], 'FontSize', 10);
    targetBtnContainer = uipanel(ctrlPanel, ...
        'Position', [152 18 MID_W-160 28], 'BorderType', 'none');
    uilabel(ctrlPanel, 'Text', '← / → arrow keys pan the view in select mode', ...
        'Position', [8 4 400 16], 'FontSize', 9, 'FontColor', [0.5 0.5 0.5]);

    % ----------------------------------------------------------------
    % Right: Sort Settings panel
    % ----------------------------------------------------------------
    SS_H = 150;
    SS_Y = CONTENT_H - SS_H;
    sortSettingsPanel = uipanel(fig, 'Title', 'Sort Settings', ...
        'Position', [MID_X+MID_W SS_Y RIGHT_W SS_H]);

    uilabel(sortSettingsPanel, 'Text', 'Method:', 'Position', [8 100 55 20]);
    methodDropdown = uidropdown(sortSettingsPanel, ...
        'Items', {'sortSpikes', 'sortSpikesByBurst'}, ...
        'Value', 'sortSpikes', ...
        'Position', [68 100 RIGHT_W-76 22]);

    uilabel(sortSettingsPanel, 'Text', 'Exclude spikes from:', ...
        'Position', [8 72 150 20]);
    filterDropdown = uidropdown(sortSettingsPanel, ...
        'Items', {'(none)'}, 'Value', '(none)', ...
        'Position', [8 50 RIGHT_W-16 22], ...
        'ValueChangedFcn', @(~,~) updateFilterStatus());

    filterStatusLabel = uilabel(sortSettingsPanel, ...
        'Text', '', 'Position', [8 8 RIGHT_W-16 38], ...
        'FontColor', [0.4 0.4 0.4], 'FontSize', 10, 'WordWrap', 'on');

    % ----------------------------------------------------------------
    % Right: Neuron Labels panel
    % ----------------------------------------------------------------
    LABEL_H = CONTENT_H - SS_H;
    uipanel(fig, 'Title', 'Neuron Labels', ...
        'Position', [MID_X+MID_W 0 RIGHT_W LABEL_H]);

    RY = MID_X + MID_W;   % right column x offset

    % Bottom controls height reserved inside the Neuron Labels panel:
    %   noise btn  24  + gap 4
    %   quick btns 24  + gap 4
    %   quick label 18 + gap 4
    %   rename row 22  + gap 4
    %   rename label 18 + gap 10  (top padding)
    %   = 132 px
    BOTTOM_CTRL_H = 132;

    % Label listbox — fills the panel above the bottom controls
    labelList = uilistbox(fig, 'Items', {}, ...
        'Position', [RY+4 BOTTOM_CTRL_H+20 RIGHT_W-8 LABEL_H-BOTTOM_CTRL_H-30]);

    % --- Rename row ---
    RENAME_Y = BOTTOM_CTRL_H - 6;   % y relative to fig bottom
    uilabel(fig, 'Text', 'Rename selected:', ...
        'Position', [RY+8 RENAME_Y 150 18]);
    renameField = uieditfield(fig, 'text', ...
        'Position', [RY+8 RENAME_Y-22 RIGHT_W-80 22], ...
        'Placeholder', 'New name…');
    uibutton(fig, 'Text', 'Rename', ...
        'Position', [RY+RIGHT_W-68 RENAME_Y-22 60 22], ...
        'ButtonPushedFcn', @(~,~) onRename());

    % --- Quick-assign named neurons ---
    QUICK_Y = RENAME_Y - 50;
    uilabel(fig, 'Text', 'Quick assign:', ...
        'Position', [RY+8 QUICK_Y 100 18]);
    quickNames = {'LP','PD','PY','LG','LPG'};
    for qi = 1:numel(quickNames)
        uibutton(fig, 'Text', quickNames{qi}, ...
            'Position', [RY+8+(qi-1)*50 QUICK_Y-26 46 24], ...
            'ButtonPushedFcn', @(~,~) onQuickAssign(quickNames{qi}));
    end

    % --- Noise quick-assign at very bottom ---
    uibutton(fig, 'Text', 'noise', ...
        'Position', [RY+8 QUICK_Y-54 RIGHT_W-16 24], ...
        'BackgroundColor', NOISE_COLOR, 'FontColor', [1 1 1], ...
        'ButtonPushedFcn', @(~,~) onQuickAssign(NOISE_GROUP));

    %% ---- Callbacks: loading ------------------------------------------

    function onLoad()
        nb   = nbField.Value;
        page = pageField.Value;
        rng  = rangeDropdown.Value;
        setStatus(sprintf('Loading NB %d page %d (%s)…', nb, page, rng));
        try
            state.experiment = loadExperiment(nb, page, rng);
        catch e
            setStatus(['Load error: ' e.message]); return
        end
        state.results = struct();
        state.channel = '';
        state.fileIdx = 1;
        undoStack     = {};
        clearSelectionSilent();
        filterDropdown.Items = {'(none)'};
        filterDropdown.Value = '(none)';
        filterStatusLabel.Text = '';

        recorded     = fieldnames(state.experiment);
        nervePresent = recorded(ismember(recorded, NERVE_CHANNELS));
        channelList.Items = nervePresent';
        if ~isempty(nervePresent)
            channelList.Value = nervePresent{1};
            onChannelSelected(nervePresent{1});
        end
        setStatus(sprintf('Loaded NB %d page %d  |  channels: %s', ...
            nb, page, strjoin(nervePresent, ', ')));
    end

    function onChannelSelected(channel)
        if isempty(state.experiment) || ~isfield(state.experiment, channel)
            return
        end
        state.channel = channel;
        state.fileIdx = 1;
        nFiles = numel(state.experiment.(channel));
        if ~isfield(state.results, channel) || ...
                numel(state.results.(channel)) ~= nFiles
            state.results.(channel) = cell(1, nFiles);
        end
        clearSelectionSilent();
        refreshFileList();
        loadCurrentFile();
        sortBtn.Enable    = 'on';
        sortAllBtn.Enable = 'on';
    end

    function onFileSelected(listValue)
        items = fileList.Items;
        idx   = find(strcmp(items, listValue), 1);
        if isempty(idx), return, end
        state.fileIdx = idx;
        clearSelectionSilent();
        loadCurrentFile();
    end

    function loadCurrentFile()
        ch = state.channel;
        fi = state.fileIdx;
        if isempty(ch) || isempty(state.experiment), return, end

        sweeps      = state.experiment.(ch);
        state.trace = sweeps{fi}(:);

        plotTrace();
        plotISI();
        updateNavButtons();
        refreshFilterDropdown();

        sg = state.results.(ch){fi};
        if ~isempty(sg)
            refreshLabelList(sg);
            buildTargetButtons(sg);
            nTotal = countSpikes(sg);
            infoLabel.Text = sprintf('File %d/%d  |  %d spikes in %d group(s)', ...
                fi, numel(sweeps), nTotal, numel(fieldnames(sg)));
        else
            labelList.Items = {};
            clearTargetButtons();
            infoLabel.Text = sprintf('File %d/%d  |  not yet sorted', ...
                fi, numel(sweeps));
        end
    end

    %% ---- Sort settings helpers ---------------------------------------

    function refreshFilterDropdown()
        fi      = state.fileIdx;
        ch      = state.channel;
        prevSel = filterDropdown.Value;
        items   = {'(none)'};
        if ~isempty(state.experiment)
            recorded     = fieldnames(state.experiment);
            nervePresent = recorded(ismember(recorded, NERVE_CHANNELS));
            for ni = 1:numel(nervePresent)
                other = nervePresent{ni};
                if strcmp(other, ch), continue, end
                if isfield(state.results, other) && ...
                        numel(state.results.(other)) >= fi && ...
                        ~isempty(state.results.(other){fi})
                    items{end+1} = other; %#ok<AGROW>
                end
            end
        end
        filterDropdown.Items = items;
        if ismember(prevSel, items)
            filterDropdown.Value = prevSel;
        else
            filterDropdown.Value = '(none)';
        end
        updateFilterStatus();
    end

    function updateFilterStatus()
        sel = filterDropdown.Value;
        fi  = state.fileIdx;
        if strcmp(sel, '(none)')
            filterStatusLabel.Text = 'No spike filter applied.';
        elseif isfield(state.results, sel) && ...
                numel(state.results.(sel)) >= fi && ...
                ~isempty(state.results.(sel){fi})
            n = countSpikes(state.results.(sel){fi});
            filterStatusLabel.Text = sprintf('%d spikes from %s will be excluded.', n, sel);
        else
            filterStatusLabel.Text = sprintf('%s not yet sorted for this file.', sel);
        end
    end

    function exclude = getFilterSpikes(fi)
        exclude = [];
        if strcmp(methodDropdown.Value, 'sortSpikesByBurst'), return, end
        sel = filterDropdown.Value;
        if strcmp(sel, '(none)'), return, end
        if ~isfield(state.results, sel), return, end
        if numel(state.results.(sel)) < fi, return, end
        if isempty(state.results.(sel){fi}), return, end
        sg     = state.results.(sel){fi};
        groups = fieldnames(sg);
        for gi = 1:numel(groups)
            exclude = [exclude; sg.(groups{gi})(:)]; %#ok<AGROW>
        end
        exclude = sort(exclude);
    end

    function sg = runSort(v, fi)
        method  = methodDropdown.Value;
        exclude = getFilterSpikes(fi);
        if strcmp(method, 'sortSpikesByBurst')
            [sg, ~] = sortSpikesByBurst(v);
        elseif isempty(exclude)
            [sg, ~] = sortSpikes(v);
        else
            [sg, ~] = sortSpikes(v, exclude, 0);
        end
        % Ensure noise group always exists
        if ~isfield(sg, NOISE_GROUP)
            sg.(NOISE_GROUP) = [];
        end
    end

    function s = filterSuffix(fi)
        exclude = getFilterSpikes(fi);
        if isempty(exclude), s = '';
        else, s = sprintf(', excl. %d from %s', numel(exclude), filterDropdown.Value);
        end
    end

    %% ---- Callbacks: sorting ------------------------------------------

    function onSort()
        if isempty(state.trace), setStatus('No file loaded.'); return, end
        ch = state.channel; fi = state.fileIdx;
        setStatus(sprintf('Sorting %s file %d  [%s%s]…', ...
            ch, fi, methodDropdown.Value, filterSuffix(fi)));
        sortBtn.Enable = 'off'; drawnow;
        try
            sg = runSort(state.trace, fi);
        catch e
            setStatus(['Sort error: ' e.message]);
            sortBtn.Enable = 'on'; return
        end
        pushUndo(ch, fi);
        state.results.(ch){fi} = sg;
        sortBtn.Enable = 'on'; exportBtn.Enable = 'on'; selectBtn.Enable = 'on';
        clearSelectionSilent();
        plotTrace(); plotISI();
        refreshLabelList(sg); buildTargetButtons(sg); refreshFileList();
        refreshFilterDropdown();
        infoLabel.Text = sprintf('File %d  |  %d spikes in %d group(s)', ...
            fi, countSpikes(sg), numel(fieldnames(sg)));
        setStatus(sprintf('Done: %s file %d.', ch, fi));
    end

    function onSortAll()
        ch     = state.channel;
        nFiles = numel(state.experiment.(ch));
        sortBtn.Enable = 'off'; sortAllBtn.Enable = 'off'; exportBtn.Enable = 'off';
        for fi = 1:nFiles
            progressLabel.Text = sprintf('Sorting file %d / %d  [%s%s]…', ...
                fi, nFiles, methodDropdown.Value, filterSuffix(fi));
            drawnow;
            sweeps        = state.experiment.(ch);
            state.trace   = sweeps{fi}(:);
            state.fileIdx = fi;
            try
                sg = runSort(state.trace, fi);
                state.results.(ch){fi} = sg;
            catch e
                setStatus(sprintf('Error on file %d: %s', fi, e.message));
            end
            refreshFileList();
            fileList.Value = fileList.Items{fi};
        end
        loadCurrentFile();
        progressLabel.Text = sprintf('All %d files sorted.', nFiles);
        sortBtn.Enable = 'on'; sortAllBtn.Enable = 'on';
        exportBtn.Enable = 'on'; selectBtn.Enable = 'on';
        setStatus(sprintf('Sorted all %d files for %s.', nFiles, ch));
    end

    function stepFile(delta)
        ch     = state.channel;
        nFiles = numel(state.experiment.(ch));
        newIdx = state.fileIdx + delta;
        if newIdx < 1 || newIdx > nFiles, return, end
        state.fileIdx  = newIdx;
        fileList.Value = fileList.Items{newIdx};
        clearSelectionSilent();
        loadCurrentFile();
    end

    %% ---- ISI panel ---------------------------------------------------

    function plotISI()
        cla(isiAx);
        ch = state.channel;
        fi = state.fileIdx;
        if isempty(ch) || isempty(state.results) || ...
                ~isfield(state.results, ch) || ...
                isempty(state.results.(ch)) || ...
                isempty(state.results.(ch){fi})
            return
        end
        sg     = state.results.(ch){fi};
        groups = fieldnames(sg);
        hold(isiAx, 'on');
        hasData = false;
        for gi = 1:numel(groups)
            times = sort(sg.(groups{gi})(:));
            if numel(times) < 2, continue, end
            isis  = diff(times);
            % Plot ISI at the time of the later spike
            tIsi  = times(2:end);
            color = isiGroupColor(gi, groups{gi});
            scatter(isiAx, tIsi, isis, 12, color, 'filled', ...
                'DisplayName', groups{gi}, 'HitTest', 'off');
            hasData = true;
        end
        hold(isiAx, 'off');
        if hasData
            legend(isiAx, 'Location', 'northeast', 'FontSize', 8);
        end
        % Fix x-axis to full file duration, no interaction
        tEnd = length(state.trace) / Fs;
        isiAx.XLim = [0 tEnd];
        isiAx.XLabel.String = 'Time (s)';
        isiAx.YLabel.String = 'ISI (s)';
        isiAx.YScale = 'log';
        isiAx.ButtonDownFcn = @onIsiClick;
        drawnow;
    end

    function color = isiGroupColor(gi, gname)
        if strcmp(gname, NOISE_GROUP)
            color = NOISE_COLOR;
        else
            color = GROUP_COLORS(mod(gi-1, size(GROUP_COLORS,1))+1, :);
        end
    end

    function onIsiClick(~, event)
        % Jump trace view to be centred on the clicked time,
        % preserving the current x-zoom width.
        clickT  = event.IntersectionPoint(1);
        curXLim = traceAx.XLim;
        halfWin = (curXLim(2) - curXLim(1)) / 2;
        tEnd    = length(state.trace) / Fs;
        newLo   = max(0,    clickT - halfWin);
        newHi   = min(tEnd, clickT + halfWin);
        % If we hit a boundary, shift the other side to keep width
        if newLo == 0,    newHi = min(tEnd, 2*halfWin); end
        if newHi == tEnd, newLo = max(0, tEnd - 2*halfWin); end
        traceAx.XLim = [newLo newHi];
    end

    %% ---- Keyboard panning --------------------------------------------

    function onKeyPress(~, event)
        if ~edit.active, return, end
        if isempty(state.trace), return, end
        switch event.Key
            case 'rightarrow'
                panTrace(+1);
            case 'leftarrow'
                panTrace(-1);
        end
    end

    function panTrace(direction)
        % Step the trace view left or right by one window width.
        curXLim = traceAx.XLim;
        winW    = curXLim(2) - curXLim(1);
        tEnd    = length(state.trace) / Fs;
        newLo   = curXLim(1) + direction * winW;
        newLo   = max(0,          newLo);
        newLo   = min(tEnd - winW, newLo);
        traceAx.XLim = [newLo  newLo + winW];
    end

    %% ---- Manual correction -------------------------------------------

    function toggleSelectMode()
        edit.active = ~edit.active;
        if edit.active
            selectBtn.Text            = '⊙  Select Mode: ON';
            selectBtn.BackgroundColor = [0.95 0.85 0.3];
            clearSelBtn.Enable        = 'on';
            setStatus('Select mode ON — click spike or drag x-range. Arrow keys pan.');
        else
            selectBtn.Text            = '⊙  Select Mode: OFF';
            selectBtn.BackgroundColor = [0.96 0.96 0.96];
            clearSelBtn.Enable        = 'off';
            clearSelection();
        end
    end

    function onAxesClick(~, event)
        if ~edit.active, return, end
        edit.dragStart  = event.IntersectionPoint(1);
        edit.isDragging = false;
    end

    function onMouseMove(~, ~)
        if ~edit.active || isempty(edit.dragStart), return, end
        curX = get(traceAx, 'CurrentPoint');
        curX = curX(1,1);
        if abs(curX - edit.dragStart) > 0.005
            edit.isDragging = true;
            plotTrace();
            xline(traceAx, edit.dragStart, '--', ...
                'Color', [0.2 0.5 1.0], 'LineWidth', 1.5, ...
                'HitTest', 'off', 'HandleVisibility', 'off');
            xline(traceAx, curX, '--', ...
                'Color', [0.2 0.5 1.0], 'LineWidth', 1.5, ...
                'HitTest', 'off', 'HandleVisibility', 'off');
            drawnow limitrate;
        end
    end

    function onMouseUp(~, ~)
        if ~edit.active || isempty(edit.dragStart), return, end
        ch = state.channel; fi = state.fileIdx;
        sg = state.results.(ch){fi};
        if isempty(sg), edit.dragStart = []; return, end

        curX = get(traceAx, 'CurrentPoint');
        curX = curX(1,1);

        if edit.isDragging
            xLo = min(edit.dragStart, curX);
            xHi = max(edit.dragStart, curX);
            edit.selected = selectSpikesInRange(sg, xLo, xHi);
        else
            edit.selected = selectNearestSpike(sg, edit.dragStart);
        end
        edit.dragStart  = [];
        edit.isDragging = false;
        selCountLabel.Text = sprintf('%d spike(s) selected', numel(edit.selected));
        plotTrace();
    end

    function spikeTimes = selectSpikesInRange(sg, xLo, xHi)
        groups = fieldnames(sg); spikeTimes = [];
        for gi = 1:numel(groups)
            times = sg.(groups{gi})(:);
            spikeTimes = [spikeTimes; times(times >= xLo & times <= xHi)]; %#ok<AGROW>
        end
        spikeTimes = sort(spikeTimes);
    end

    function spikeTime = selectNearestSpike(sg, clickX)
        groups = fieldnames(sg); allTimes = [];
        for gi = 1:numel(groups)
            allTimes = [allTimes; sg.(groups{gi})(:)]; %#ok<AGROW>
        end
        if isempty(allTimes), spikeTime = []; return, end
        [~, idx] = min(abs(allTimes - clickX));
        spikeTime = allTimes(idx);
    end

    function reassignSelected(targetGroup)
        if isempty(edit.selected), return, end
        ch = state.channel; fi = state.fileIdx;
        sg = state.results.(ch){fi};
        if isempty(sg), return, end
        pushUndo(ch, fi);
        groups = fieldnames(sg);
        for gi = 1:numel(groups)
            sg.(groups{gi}) = setdiff(sg.(groups{gi})(:), edit.selected(:));
        end
        if isfield(sg, targetGroup)
            sg.(targetGroup) = sort([sg.(targetGroup)(:); edit.selected(:)]);
        else
            sg.(targetGroup) = sort(edit.selected(:));
        end
        % Ensure noise group survives even if empty
        if ~isfield(sg, NOISE_GROUP)
            sg.(NOISE_GROUP) = [];
        end
        % Remove empty non-noise groups
        groups = fieldnames(sg);
        for gi = 1:numel(groups)
            if isempty(sg.(groups{gi})) && ~strcmp(groups{gi}, NOISE_GROUP)
                sg = rmfield(sg, groups{gi});
            end
        end
        state.results.(ch){fi} = sg;
        clearSelectionSilent();
        plotTrace(); plotISI();
        refreshLabelList(sg); buildTargetButtons(sg); refreshFileList();
        infoLabel.Text = sprintf('File %d  |  %d spikes in %d group(s)', ...
            fi, countSpikes(sg), numel(fieldnames(sg)));
    end

    function clearSelection()
        clearSelectionSilent();
        plotTrace();
    end

    function clearSelectionSilent()
        % Reset selection state without forcing a redraw
        edit.selected   = [];
        edit.dragStart  = [];
        edit.isDragging = false;
        if isvalid(fig)
            selCountLabel.Text = '0 spikes selected';
        end
    end

    %% ---- Labeling ----------------------------------------------------

    function onRename()
        ch = state.channel; fi = state.fileIdx;
        sg = state.results.(ch){fi};
        if isempty(sg), return, end
        selected = labelList.Value;
        newName  = strtrim(renameField.Value);
        if isempty(selected) || isempty(newName), return, end
        oldName = extractGroupName(selected);
        if strcmp(oldName, NOISE_GROUP)
            setStatus('Cannot rename the noise group.');
            return
        end
        if isfield(sg, oldName) && ~isfield(sg, newName)
            pushUndo(ch, fi);
            sg.(newName) = sg.(oldName);
            sg = rmfield(sg, oldName);
            state.results.(ch){fi} = sg;
            refreshLabelList(sg); buildTargetButtons(sg); plotTrace(); plotISI();
        end
        renameField.Value = '';
    end

    function onQuickAssign(label)
        ch = state.channel; fi = state.fileIdx;
        sg = state.results.(ch){fi};
        if isempty(sg) || isempty(labelList.Value), return, end
        oldName = extractGroupName(labelList.Value);
        if isfield(sg, oldName)
            pushUndo(ch, fi);
            if isfield(sg, label)
                sg.(label) = [sg.(label) sg.(oldName)];
            else
                sg.(label) = sg.(oldName);
            end
            % Keep noise group even if now empty
            if ~strcmp(oldName, NOISE_GROUP)
                sg = rmfield(sg, oldName);
            end
            if ~isfield(sg, NOISE_GROUP)
                sg.(NOISE_GROUP) = [];
            end
            state.results.(ch){fi} = sg;
            refreshLabelList(sg); buildTargetButtons(sg);
            refreshFileList(); plotTrace(); plotISI();
        end
    end

    function onExport()
        ch = state.channel;
        if isempty(ch) || ~isfield(state.results, ch), return, end
        nb   = nbField.Value; page = pageField.Value;
        defaultName = sprintf('NB%d_p%d_%s_allFiles.mat', nb, page, ch);
        [f, p] = uiputfile('*.mat', 'Export all sorted files', defaultName);
        if isequal(f, 0), return, end
        results = struct(); %#ok<NASGU>
        nFiles  = numel(state.results.(ch));
        for fi = 1:nFiles
            key = sprintf('file%d', fi);
            if ~isempty(state.results.(ch){fi})
                results.(key) = state.results.(ch){fi};
            end
        end
        save(fullfile(p, f), 'results');
        setStatus(['Exported to ' fullfile(p, f)]);
    end

    %% ---- Undo --------------------------------------------------------

    function pushUndo(ch, fi)
        entry.ch = ch; entry.fi = fi;
        entry.sg = state.results.(ch){fi};
        undoStack{end+1} = entry;
        undoBtn.Enable = 'on';
        if numel(undoStack) > 20
            undoStack = undoStack(end-19:end);
        end
    end

    function onUndo()
        if isempty(undoStack), return, end
        entry = undoStack{end};
        undoStack(end) = [];
        state.results.(entry.ch){entry.fi} = entry.sg;
        if isempty(undoStack), undoBtn.Enable = 'off'; end
        clearSelectionSilent();
        loadCurrentFile();
        setStatus('Undo applied.');
    end

    %% ---- Plotting ----------------------------------------------------

    function plotTrace()
        % Preserve current XLim if set (so panning / zoom survives redraws)
        if ~isempty(state.trace) && ~isequal(traceAx.XLim, [0 1])
            prevXLim = traceAx.XLim;
        else
            prevXLim = [];
        end

        cla(traceAx);
        if isempty(state.trace), return, end

        t = (0:length(state.trace)-1) / Fs;
        plot(traceAx, t, state.trace, 'Color', [0.2 0.2 0.2], 'LineWidth', 0.4);
        hold(traceAx, 'on');

        ch = state.channel; fi = state.fileIdx;
        sg = state.results.(ch){fi};

        if ~isempty(sg)
            groups = fieldnames(sg);
            for gi = 1:numel(groups)
                times = sg.(groups{gi});
                times = times(times >= t(1) & times <= t(end));
                amps  = interp1(t, state.trace, times, 'linear', 0);
                color = traceGroupColor(gi, groups{gi});
                isSel = ismember(times, edit.selected);
                if any(~isSel)
                    scatter(traceAx, times(~isSel), amps(~isSel), 20, ...
                        color, 'filled', 'DisplayName', groups{gi}, ...
                        'HitTest', 'off');
                end
                if any(isSel)
                    scatter(traceAx, times(isSel), amps(isSel), 40, ...
                        SEL_COLOR, 'filled', 'MarkerEdgeColor', [0 0 0], ...
                        'LineWidth', 1.0, 'DisplayName', '', 'HitTest', 'off');
                end
            end
            legend(traceAx, 'Location', 'northeast');
        end

        hold(traceAx, 'off');
        title(traceAx, sprintf('%s  —  file %d', ch, fi));
        traceAx.XLabel.String = 'Time (s)';
        traceAx.YLabel.String = 'mV';
        traceAx.ButtonDownFcn = @onAxesClick;

        % Restore zoom position if we had one
        if ~isempty(prevXLim)
            tEnd = t(end);
            newLo = max(0, prevXLim(1));
            newHi = min(tEnd, prevXLim(2));
            if newHi > newLo
                traceAx.XLim = [newLo newHi];
            end
        end
        drawnow;
    end

    function color = traceGroupColor(gi, gname)
        if strcmp(gname, NOISE_GROUP)
            color = NOISE_COLOR;
        else
            color = GROUP_COLORS(mod(gi-1, size(GROUP_COLORS,1))+1, :);
        end
    end

    %% ---- UI helpers --------------------------------------------------

    function buildTargetButtons(sg)
        delete(targetBtnContainer.Children);
        if isempty(sg) || ~isstruct(sg), return, end
        % Always show noise button first (grey), then other groups
        allGroups  = fieldnames(sg);
        noiseFirst = [allGroups(strcmp(allGroups, NOISE_GROUP)); ...
                      allGroups(~strcmp(allGroups, NOISE_GROUP))];
        x = 4; btnW = 66; gap = 4;
        for gi = 1:numel(noiseFirst)
            gname = noiseFirst{gi};
            if strcmp(gname, NOISE_GROUP)
                color = NOISE_COLOR; fc = [1 1 1];
            else
                color = GROUP_COLORS(mod(gi-1, size(GROUP_COLORS,1))+1, :);
                lum   = 0.299*color(1) + 0.587*color(2) + 0.114*color(3);
                fc    = [0 0 0]; if lum < 0.55, fc = [1 1 1]; end
            end
            uibutton(targetBtnContainer, 'Text', gname, ...
                'Position', [x 1 btnW 22], ...
                'BackgroundColor', color, 'FontColor', fc, ...
                'ButtonPushedFcn', @(~,~) reassignSelected(gname));
            x = x + btnW + gap;
        end
    end

    function clearTargetButtons()
        delete(targetBtnContainer.Children);
    end

    function refreshLabelList(sg)
        if isempty(sg) || ~isstruct(sg)
            labelList.Items = {}; return
        end
        groups = fieldnames(sg);
        items  = cellfun(@(g) sprintf('%s  (%d spikes)', g, length(sg.(g))), ...
            groups, 'UniformOutput', false);
        labelList.Items = items';
        if ~isempty(items), labelList.Value = items{1}; end
    end

    function refreshFileList()
        ch = state.channel;
        if isempty(ch) || ~isfield(state.experiment, ch), return, end
        nFiles = numel(state.experiment.(ch));
        items  = cell(1, nFiles);
        for fi = 1:nFiles
            sg = state.results.(ch){fi};
            if isempty(sg)
                badge = '○';
            else
                gnames = fieldnames(sg);
                named  = gnames(~strcmp(gnames, NOISE_GROUP) & ...
                                ~startsWith(gnames, 'spikeTimes'));
                if ~isempty(named)
                    badge = ['✓ ' strjoin(named, ' ')];
                else
                    badge = sprintf('✓ %d groups', numel(gnames));
                end
            end
            items{fi} = sprintf('File %02d  %s', fi, badge);
        end
        fileList.Items = items;
        if state.fileIdx <= nFiles
            fileList.Value = items{state.fileIdx};
        end
    end

    function updateNavButtons()
        ch     = state.channel;
        nFiles = numel(state.experiment.(ch));
        prevBtn.Enable      = onOff(state.fileIdx > 1);
        nextBtn.Enable      = onOff(state.fileIdx < nFiles);
        fileCountLabel.Text = sprintf('File %d of %d', state.fileIdx, nFiles);
    end

    function n = countSpikes(sg)
        if isempty(sg) || ~isstruct(sg), n = 0; return, end
        groups = fieldnames(sg);
        n = sum(cellfun(@(g) length(sg.(g)), groups));
    end

    function name = extractGroupName(listItem)
        name = strtrim(regexp(listItem, '^[^\s(]+', 'match', 'once'));
    end

    function s = onOff(tf)
        if tf, s = 'on'; else, s = 'off'; end
    end

    function setStatus(msg)
        statusLabel.Text = msg; drawnow;
    end

end