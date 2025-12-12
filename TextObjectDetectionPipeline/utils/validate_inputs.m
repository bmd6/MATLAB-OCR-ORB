function [isValid, errorMsg] = validate_inputs(inputImagePath, referenceDir, config)
%VALIDATE_INPUTS Validate all pipeline inputs before processing
%
%   [ISVALID, ERRORMSG] = VALIDATE_INPUTS(INPUTIMAGEPATH, REFERENCEDIR, CONFIG)
%   performs comprehensive validation of all inputs to the pipeline.
%
%   Inputs:
%       inputImagePath - Path to the input image file
%       referenceDir   - Path to the reference images directory
%       config         - Configuration structure from default_config()
%
%   Outputs:
%       isValid  - Boolean indicating if all inputs are valid
%       errorMsg - Cell array of error messages (empty if valid)
%
%   Validates:
%       - Input image exists and is a supported format
%       - Reference directory exists
%       - At least one reference image or text file exists
%       - Configuration structure has required fields
%       - Image can be read (not corrupt)
%       - Image dimensions are reasonable
%
%   Example:
%       config = default_config();
%       [valid, errors] = validate_inputs('test.png', './refs', config);
%       if ~valid
%           disp(errors);
%       end
%
%   See also: DEFAULT_CONFIG, IMAGE_LOADER

    %% Initialize
    isValid = true;
    errorMsg = {};
    
    %% Validate Input Image Path
    if isempty(inputImagePath)
        isValid = false;
        errorMsg{end+1} = 'Input image path is empty.';
    elseif ~isfile(inputImagePath)
        isValid = false;
        errorMsg{end+1} = sprintf('Input image file not found: %s', inputImagePath);
    else
        % Check file extension
        [~, ~, ext] = fileparts(inputImagePath);
        ext = lower(ext);
        
        if ~ismember(ext, config.supportedFormats)
            isValid = false;
            errorMsg{end+1} = sprintf('Unsupported image format: %s. Supported: %s', ...
                ext, strjoin(config.supportedFormats, ', '));
        else
            % Try to read image info
            try
                imgInfo = imfinfo(inputImagePath);
                
                % Check dimensions
                if imgInfo(1).Width < 10 || imgInfo(1).Height < 10
                    isValid = false;
                    errorMsg{end+1} = sprintf('Image too small: %dx%d pixels (minimum 10x10)', ...
                        imgInfo(1).Width, imgInfo(1).Height);
                end
                
                % Check for extremely large images
                if imgInfo(1).Width > 10000 || imgInfo(1).Height > 10000
                    errorMsg{end+1} = sprintf('Warning: Very large image (%dx%d). Processing may be slow.', ...
                        imgInfo(1).Width, imgInfo(1).Height);
                    % This is a warning, not an error
                end
                
            catch ME
                isValid = false;
                errorMsg{end+1} = sprintf('Cannot read image file: %s', ME.message);
            end
        end
    end
    
    %% Validate Reference Directory
    if isempty(referenceDir)
        isValid = false;
        errorMsg{end+1} = 'Reference directory path is empty.';
    elseif ~isfolder(referenceDir)
        isValid = false;
        errorMsg{end+1} = sprintf('Reference directory not found: %s', referenceDir);
    else
        % Check for reference content
        hasImages = false;
        hasTextFile = false;
        
        % Check for images
        for i = 1:length(config.supportedFormats)
            ext = config.supportedFormats{i};
            files = dir(fullfile(referenceDir, ['*' ext]));
            filesUpper = dir(fullfile(referenceDir, ['*' upper(ext)]));
            
            if ~isempty(files) || ~isempty(filesUpper)
                hasImages = true;
                break;
            end
        end
        
        % Check for reference text file
        textFilePath = fullfile(referenceDir, config.referenceText.fileName);
        if isfile(textFilePath)
            hasTextFile = true;
        end
        
        if ~hasImages && ~hasTextFile
            isValid = false;
            errorMsg{end+1} = sprintf('No reference images or text file found in: %s', referenceDir);
        end
        
        if ~hasImages
            errorMsg{end+1} = 'Warning: No reference images found. Object detection will be skipped.';
        end
        
        if ~hasTextFile
            errorMsg{end+1} = sprintf('Warning: Reference text file not found (%s). Text matching will be limited.', ...
                config.referenceText.fileName);
        end
    end
    
    %% Validate Configuration Structure
    requiredFields = {'ocr', 'orb', 'preprocessing', 'visualization', 'processing', ...
        'supportedFormats', 'referenceText', 'accuracy', 'exclusion'};
    
    for i = 1:length(requiredFields)
        if ~isfield(config, requiredFields{i})
            isValid = false;
            errorMsg{end+1} = sprintf('Configuration missing required field: %s', requiredFields{i});
        end
    end
    
    % Validate specific config values
    if isfield(config, 'ocr')
        if config.ocr.confidenceThreshold < 0 || config.ocr.confidenceThreshold > 100
            isValid = false;
            errorMsg{end+1} = 'OCR confidence threshold must be between 0 and 100.';
        end
    end
    
    if isfield(config, 'orb')
        if config.orb.minMatchedFeatures < 4
            isValid = false;
            errorMsg{end+1} = 'ORB minimum matched features must be at least 4 (required for homography).';
        end
        
        if config.orb.matchRatioThreshold < 0 || config.orb.matchRatioThreshold > 1
            isValid = false;
            errorMsg{end+1} = 'ORB match ratio threshold must be between 0 and 1.';
        end
        
        if config.orb.maxInstancesPerReference < 1 || config.orb.maxInstancesPerReference > 8
            errorMsg{end+1} = sprintf('Warning: maxInstancesPerReference=%d. Valid range is 1-8.', ...
                config.orb.maxInstancesPerReference);
        end
    end
    
    %% Check MATLAB Toolbox Requirements
    requiredToolboxes = {'Computer Vision Toolbox', 'Image Processing Toolbox'};
    installedToolboxes = ver;
    installedNames = {installedToolboxes.Name};
    
    for i = 1:length(requiredToolboxes)
        if ~any(contains(installedNames, requiredToolboxes{i}))
            isValid = false;
            errorMsg{end+1} = sprintf('Required toolbox not installed: %s', requiredToolboxes{i});
        end
    end
    
    %% Check for OCR Language Support
    try
        % Try to get supported languages (this validates OCR availability)
        ocrLanguages = ocr.supportedLanguages;
        
        if ~ismember(config.ocr.language, ocrLanguages)
            errorMsg{end+1} = sprintf('Warning: OCR language "%s" may not be installed. Using default.', ...
                config.ocr.language);
        end
    catch ME
        errorMsg{end+1} = sprintf('Warning: Could not verify OCR support: %s', ME.message);
    end
    
    %% Summary
    if isValid
        fprintf('[VALIDATE_INPUTS] All inputs validated successfully.\n');
    else
        fprintf('[VALIDATE_INPUTS] Validation failed with %d errors.\n', ...
            sum(~contains(errorMsg, 'Warning')));
    end
    
    % Print warnings
    warnings = errorMsg(contains(errorMsg, 'Warning'));
    for i = 1:length(warnings)
        fprintf('[VALIDATE_INPUTS] %s\n', warnings{i});
    end

end
