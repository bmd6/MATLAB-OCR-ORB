function [referenceImages, referenceText, refInfo] = load_reference_data(referenceDir, config)
%LOAD_REFERENCE_DATA Load reference images and text from directory
%
%   [REFERENCEIMAGES, REFERENCETEXT, REFINFO] = LOAD_REFERENCE_DATA(REFERENCEDIR, CONFIG)
%   loads all reference images and the reference text file from the
%   specified directory.
%
%   Inputs:
%       referenceDir - Path to directory containing reference images and text
%       config       - Configuration structure from default_config()
%
%   Outputs:
%       referenceImages - Structure array with fields:
%                         .name       - File name without extension
%                         .image      - Original color image
%                         .gray       - Grayscale version
%                         .features   - ORB features (if caching enabled)
%                         .points     - Feature points (if caching enabled)
%                         .scales     - Multi-scale versions (if enabled)
%       referenceText   - Cell array of expected text strings
%       refInfo         - Structure with loading statistics
%
%   Example:
%       config = default_config();
%       [refImages, refText, info] = load_reference_data('./references', config);
%
%   See also: IMAGE_LOADER, DEFAULT_CONFIG

    %% Input Validation
    if nargin < 2
        error('LOAD_REFERENCE_DATA:InvalidInput', 'Both referenceDir and config are required.');
    end
    
    if ~isfolder(referenceDir)
        error('LOAD_REFERENCE_DATA:DirectoryNotFound', ...
            'Reference directory not found: %s', referenceDir);
    end
    
    %% Initialize Output Structures
    referenceImages = struct('name', {}, 'image', {}, 'gray', {}, ...
        'features', {}, 'points', {}, 'scales', {});
    referenceText = {};
    refInfo = struct();
    refInfo.numImages = 0;
    refInfo.numTextEntries = 0;
    refInfo.loadedFiles = {};
    refInfo.failedFiles = {};
    refInfo.textFileFound = false;
    
    %% Load Reference Text File
    textFilePath = fullfile(referenceDir, config.referenceText.fileName);
    
    if isfile(textFilePath)
        try
            fid = fopen(textFilePath, 'r', 'n', config.referenceText.encoding);
            if fid == -1
                warning('LOAD_REFERENCE_DATA:TextFileError', ...
                    'Could not open reference text file: %s', textFilePath);
            else
                % Read all lines
                textContent = textscan(fid, '%s', 'Delimiter', '\n', 'WhiteSpace', '');
                fclose(fid);
                
                referenceText = textContent{1};
                
                % Remove empty lines and trim whitespace
                referenceText = referenceText(~cellfun(@isempty, referenceText));
                referenceText = strtrim(referenceText);
                
                refInfo.numTextEntries = length(referenceText);
                refInfo.textFileFound = true;
                
                if config.processing.verbose
                    fprintf('[LOAD_REFERENCE_DATA] Loaded %d text entries from %s\n', ...
                        refInfo.numTextEntries, config.referenceText.fileName);
                end
            end
        catch ME
            warning('LOAD_REFERENCE_DATA:TextFileError', ...
                'Error reading reference text file: %s', ME.message);
        end
    else
        if config.processing.verbose
            fprintf('[LOAD_REFERENCE_DATA] No reference text file found at: %s\n', textFilePath);
        end
    end
    
    %% Find Reference Images
    imageFiles = {};
    for i = 1:length(config.supportedFormats)
        ext = config.supportedFormats{i};
        files = dir(fullfile(referenceDir, ['*' ext]));
        
        % Also check uppercase extension
        filesUpper = dir(fullfile(referenceDir, ['*' upper(ext)]));
        
        for j = 1:length(files)
            imageFiles{end+1} = fullfile(referenceDir, files(j).name);
        end
        for j = 1:length(filesUpper)
            imageFiles{end+1} = fullfile(referenceDir, filesUpper(j).name);
        end
    end
    
    % Remove duplicates
    imageFiles = unique(imageFiles);
    
    if isempty(imageFiles)
        warning('LOAD_REFERENCE_DATA:NoImages', ...
            'No reference images found in directory: %s', referenceDir);
        return;
    end
    
    if config.processing.verbose
        fprintf('[LOAD_REFERENCE_DATA] Found %d reference images to load.\n', length(imageFiles));
    end
    
    %% Load Each Reference Image
    for i = 1:length(imageFiles)
        imgPath = imageFiles{i};
        [~, imgName, ~] = fileparts(imgPath);
        
        try
            % Load image
            img = imread(imgPath);
            
            % Ensure uint8
            if ~isa(img, 'uint8')
                img = im2uint8(img);
            end
            
            % Handle different color formats
            if size(img, 3) == 4
                img = img(:,:,1:3);  % Remove alpha
            end
            
            % Convert to grayscale for feature detection
            if size(img, 3) == 3
                imgGray = rgb2gray(img);
            else
                imgGray = img;
            end
            
            % Create reference entry
            refEntry = struct();
            refEntry.name = imgName;
            refEntry.image = img;
            refEntry.gray = imgGray;
            refEntry.filePath = imgPath;
            
            % Pre-compute ORB features if caching enabled
            if config.processing.cacheFeatures
                try
                    refEntry.points = detectORBFeatures(imgGray, ...
                        'NumLevels', 8, ...
                        'ScaleFactor', 1.2);
                    
                    if ~isempty(refEntry.points)
                        % Limit number of features
                        if refEntry.points.Count > config.orb.maxFeatures
                            refEntry.points = refEntry.points.selectStrongest(config.orb.maxFeatures);
                        end
                        
                        [refEntry.features, refEntry.points] = extractFeatures(imgGray, refEntry.points);
                    else
                        refEntry.features = [];
                    end
                catch
                    refEntry.features = [];
                    refEntry.points = [];
                end
            else
                refEntry.features = [];
                refEntry.points = [];
            end
            
            % Create multi-scale versions if enabled
            if config.orb.multiScale.enabled
                scales = config.orb.multiScale.scales;
                refEntry.scales = struct('scale', {}, 'gray', {}, ...
                    'features', {}, 'points', {});
                
                for s = 1:length(scales)
                    scale = scales(s);
                    
                    if scale == 1.0
                        scaledGray = imgGray;
                    else
                        scaledGray = imresize(imgGray, scale);
                    end
                    
                    scaleEntry = struct();
                    scaleEntry.scale = scale;
                    scaleEntry.gray = scaledGray;
                    
                    if config.processing.cacheFeatures
                        try
                            scaleEntry.points = detectORBFeatures(scaledGray, ...
                                'NumLevels', 8, ...
                                'ScaleFactor', 1.2);
                            
                            if ~isempty(scaleEntry.points) && scaleEntry.points.Count > 0
                                if scaleEntry.points.Count > config.orb.maxFeatures
                                    scaleEntry.points = scaleEntry.points.selectStrongest(config.orb.maxFeatures);
                                end
                                [scaleEntry.features, scaleEntry.points] = extractFeatures(scaledGray, scaleEntry.points);
                            else
                                scaleEntry.features = [];
                            end
                        catch
                            scaleEntry.features = [];
                            scaleEntry.points = [];
                        end
                    else
                        scaleEntry.features = [];
                        scaleEntry.points = [];
                    end
                    
                    refEntry.scales(end+1) = scaleEntry;
                end
            else
                refEntry.scales = [];
            end
            
            % Add to array
            referenceImages(end+1) = refEntry;
            refInfo.loadedFiles{end+1} = imgPath;
            
            if config.processing.verbose
                fprintf('[LOAD_REFERENCE_DATA] Loaded: %s (%dx%d)\n', ...
                    imgName, size(img, 2), size(img, 1));
            end
            
        catch ME
            warning('LOAD_REFERENCE_DATA:ImageLoadError', ...
                'Failed to load reference image: %s\nError: %s', imgPath, ME.message);
            refInfo.failedFiles{end+1} = imgPath;
        end
    end
    
    refInfo.numImages = length(referenceImages);
    
    if refInfo.numImages == 0
        warning('LOAD_REFERENCE_DATA:NoImagesLoaded', ...
            'No reference images were successfully loaded.');
    end

end
