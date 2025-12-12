function cache = feature_cache(action, referenceDir, config, data)
%FEATURE_CACHE Manage cached ORB features for reference images
%
%   CACHE = FEATURE_CACHE(ACTION, REFERENCEDIR, CONFIG, DATA)
%   manages a persistent cache of pre-computed ORB features.
%
%   Actions:
%       'load'   - Load cached features from disk
%       'save'   - Save computed features to disk
%       'clear'  - Clear the cache for a directory
%       'exists' - Check if cache exists and is valid
%
%   Inputs:
%       action       - Action to perform ('load', 'save', 'clear', 'exists')
%       referenceDir - Path to reference images directory
%       config       - Configuration structure from default_config()
%       data         - Data to save (only for 'save' action)
%
%   Outputs:
%       cache - Cached data (for 'load'), or status (for other actions)
%
%   Cache Validation:
%       - Checks modification times of reference images
%       - Invalidates if images have changed
%       - Stores config hash to detect parameter changes
%
%   Example:
%       config = default_config();
%       
%       % Check if cache exists
%       if feature_cache('exists', './refs', config)
%           cache = feature_cache('load', './refs', config);
%       end
%       
%       % Save cache
%       feature_cache('save', './refs', config, referenceImages);
%
%   See also: LOAD_REFERENCE_DATA, OBJECT_DETECTOR

    %% Input Validation
    if nargin < 3
        error('FEATURE_CACHE:InvalidInput', 'At least action, referenceDir, and config are required.');
    end
    
    if nargin < 4
        data = [];
    end
    
    %% Generate Cache File Path
    % Create a unique cache filename based on directory path
    dirHash = generate_hash(referenceDir);
    cacheFileName = sprintf('orb_cache_%s.mat', dirHash);
    cacheFilePath = fullfile(tempdir, cacheFileName);
    
    %% Execute Action
    switch lower(action)
        case 'load'
            cache = load_cache(cacheFilePath, referenceDir, config);
            
        case 'save'
            cache = save_cache(cacheFilePath, referenceDir, config, data);
            
        case 'clear'
            cache = clear_cache(cacheFilePath);
            
        case 'exists'
            cache = cache_exists(cacheFilePath, referenceDir, config);
            
        otherwise
            error('FEATURE_CACHE:InvalidAction', 'Unknown action: %s', action);
    end

end

%% Helper Function: Generate Hash
function hash = generate_hash(str)
%GENERATE_HASH Create a simple hash from a string
    
    % Simple hash using sum of character codes
    bytes = uint8(str);
    hash = sprintf('%08x', mod(sum(bytes .* (1:length(bytes))'), 2^32));

end

%% Helper Function: Generate Config Hash
function hash = generate_config_hash(config)
%GENERATE_CONFIG_HASH Create hash from relevant config parameters
    
    % Extract relevant ORB parameters that would affect cached features
    configStr = sprintf('%.4f_%d_%d', ...
        config.orb.matchRatioThreshold, ...
        config.orb.maxFeatures, ...
        config.orb.minMatchedFeatures);
    
    if config.orb.multiScale.enabled
        configStr = [configStr, sprintf('_%.2f', config.orb.multiScale.scales)];
    end
    
    hash = generate_hash(configStr);

end

%% Helper Function: Get Reference Files Info
function filesInfo = get_reference_files_info(referenceDir, config)
%GET_REFERENCE_FILES_INFO Get modification times of reference files
    
    filesInfo = struct('name', {}, 'date', {}, 'bytes', {});
    
    for i = 1:length(config.supportedFormats)
        ext = config.supportedFormats{i};
        files = dir(fullfile(referenceDir, ['*' ext]));
        filesUpper = dir(fullfile(referenceDir, ['*' upper(ext)]));
        
        for j = 1:length(files)
            info = struct();
            info.name = files(j).name;
            info.date = files(j).datenum;
            info.bytes = files(j).bytes;
            filesInfo(end+1) = info;
        end
        
        for j = 1:length(filesUpper)
            info = struct();
            info.name = filesUpper(j).name;
            info.date = filesUpper(j).datenum;
            info.bytes = filesUpper(j).bytes;
            filesInfo(end+1) = info;
        end
    end

end

%% Helper Function: Load Cache
function cache = load_cache(cacheFilePath, referenceDir, config)
%LOAD_CACHE Load cached features if valid
    
    cache = [];
    
    if ~isfile(cacheFilePath)
        return;
    end
    
    try
        loaded = load(cacheFilePath, 'cacheData');
        cacheData = loaded.cacheData;
        
        % Validate cache
        if ~isfield(cacheData, 'configHash') || ...
           ~isfield(cacheData, 'filesInfo') || ...
           ~isfield(cacheData, 'referenceImages')
            warning('FEATURE_CACHE:InvalidCache', 'Cache structure invalid. Ignoring cache.');
            return;
        end
        
        % Check config hash
        currentConfigHash = generate_config_hash(config);
        if ~strcmp(cacheData.configHash, currentConfigHash)
            fprintf('[FEATURE_CACHE] Configuration changed. Cache invalidated.\n');
            return;
        end
        
        % Check file modification times
        currentFilesInfo = get_reference_files_info(referenceDir, config);
        
        if length(cacheData.filesInfo) ~= length(currentFilesInfo)
            fprintf('[FEATURE_CACHE] Number of reference files changed. Cache invalidated.\n');
            return;
        end
        
        % Compare each file
        for i = 1:length(currentFilesInfo)
            found = false;
            for j = 1:length(cacheData.filesInfo)
                if strcmp(currentFilesInfo(i).name, cacheData.filesInfo(j).name)
                    if currentFilesInfo(i).date > cacheData.filesInfo(j).date
                        fprintf('[FEATURE_CACHE] File %s modified. Cache invalidated.\n', ...
                            currentFilesInfo(i).name);
                        return;
                    end
                    found = true;
                    break;
                end
            end
            
            if ~found
                fprintf('[FEATURE_CACHE] New file detected: %s. Cache invalidated.\n', ...
                    currentFilesInfo(i).name);
                return;
            end
        end
        
        % Cache is valid
        cache = cacheData.referenceImages;
        fprintf('[FEATURE_CACHE] Loaded %d cached reference images.\n', length(cache));
        
    catch ME
        warning('FEATURE_CACHE:LoadError', 'Error loading cache: %s', ME.message);
        cache = [];
    end

end

%% Helper Function: Save Cache
function status = save_cache(cacheFilePath, referenceDir, config, data)
%SAVE_CACHE Save features to cache
    
    status = false;
    
    if isempty(data)
        warning('FEATURE_CACHE:NoData', 'No data to save.');
        return;
    end
    
    try
        cacheData = struct();
        cacheData.configHash = generate_config_hash(config);
        cacheData.filesInfo = get_reference_files_info(referenceDir, config);
        cacheData.referenceImages = data;
        cacheData.timestamp = datetime('now');
        cacheData.referenceDir = referenceDir;
        
        save(cacheFilePath, 'cacheData', '-v7.3');
        
        fprintf('[FEATURE_CACHE] Saved %d reference images to cache.\n', length(data));
        status = true;
        
    catch ME
        warning('FEATURE_CACHE:SaveError', 'Error saving cache: %s', ME.message);
    end

end

%% Helper Function: Clear Cache
function status = clear_cache(cacheFilePath)
%CLEAR_CACHE Delete cache file
    
    status = false;
    
    if isfile(cacheFilePath)
        try
            delete(cacheFilePath);
            fprintf('[FEATURE_CACHE] Cache cleared.\n');
            status = true;
        catch ME
            warning('FEATURE_CACHE:ClearError', 'Error clearing cache: %s', ME.message);
        end
    else
        fprintf('[FEATURE_CACHE] No cache to clear.\n');
        status = true;
    end

end

%% Helper Function: Check Cache Exists
function exists = cache_exists(cacheFilePath, referenceDir, config)
%CACHE_EXISTS Check if valid cache exists
    
    exists = false;
    
    if ~isfile(cacheFilePath)
        return;
    end
    
    % Try to load and validate
    cache = load_cache(cacheFilePath, referenceDir, config);
    exists = ~isempty(cache);

end
