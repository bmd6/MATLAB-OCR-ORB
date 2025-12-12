function [processedImage, preprocessInfo] = preprocessor(inputImage, config, roi, useROI)
%PREPROCESSOR Apply image preprocessing and enhancement
%
%   [PROCESSEDIMAGE, PREPROCESSINFO] = PREPROCESSOR(INPUTIMAGE, CONFIG, ROI, USEROI)
%   applies various preprocessing steps to enhance the image for detection.
%
%   Inputs:
%       inputImage - Input image (RGB or grayscale)
%       config     - Configuration structure from default_config()
%       roi        - Region of interest [x, y, width, height] (optional)
%       useROI     - Boolean flag to use ROI (optional)
%
%   Outputs:
%       processedImage - Enhanced image ready for detection
%       preprocessInfo - Structure with preprocessing details:
%                        .enhancementApplied - Description of applied enhancements
%                        .originalSize       - Original image dimensions
%                        .processedSize      - Processed image dimensions
%                        .roiApplied         - Whether ROI was used
%
%   Enhancement options (configured in default_config):
%       - Contrast enhancement (adaptive histogram equalization)
%       - Denoising (Gaussian or median filter)
%       - Sharpening
%       - Resizing for large images
%
%   Example:
%       config = default_config();
%       [enhanced, info] = preprocessor(img, config, [], false);
%
%   See also: ADAPTHISTEQ, IMGAUSSFILT, IMSHARPEN, IMRESIZE

    %% Input Validation
    if nargin < 2
        error('PREPROCESSOR:InvalidInput', 'inputImage and config are required.');
    end
    
    if nargin < 3 || isempty(roi)
        roi = [];
    end
    
    if nargin < 4
        useROI = false;
    end
    
    %% Initialize Output
    processedImage = inputImage;
    preprocessInfo = struct();
    preprocessInfo.enhancementApplied = 'None';
    preprocessInfo.originalSize = size(inputImage);
    preprocessInfo.roiApplied = false;
    preprocessInfo.steps = {};
    
    %% Validate Input Image
    if isempty(inputImage)
        error('PREPROCESSOR:EmptyImage', 'Input image is empty.');
    end
    
    [height, width, channels] = size(inputImage);
    
    %% Apply ROI if specified
    if useROI && ~isempty(roi)
        try
            % Validate ROI
            roiX = max(1, round(roi(1)));
            roiY = max(1, round(roi(2)));
            roiWidth = min(round(roi(3)), width - roiX + 1);
            roiHeight = min(round(roi(4)), height - roiY + 1);
            
            if roiWidth > 0 && roiHeight > 0
                processedImage = inputImage(roiY:roiY+roiHeight-1, roiX:roiX+roiWidth-1, :);
                preprocessInfo.roiApplied = true;
                preprocessInfo.roi = [roiX, roiY, roiWidth, roiHeight];
                preprocessInfo.steps{end+1} = sprintf('ROI applied: [%d, %d, %d, %d]', ...
                    roiX, roiY, roiWidth, roiHeight);
                
                if config.processing.verbose
                    fprintf('[PREPROCESSOR] ROI applied: [%d, %d, %d, %d]\n', ...
                        roiX, roiY, roiWidth, roiHeight);
                end
            else
                warning('PREPROCESSOR:InvalidROI', 'Invalid ROI dimensions. Processing full image.');
            end
        catch ME
            warning('PREPROCESSOR:ROIError', 'Error applying ROI: %s. Processing full image.', ME.message);
        end
    end
    
    %% Check if preprocessing is enabled
    if ~config.preprocessing.enabled
        preprocessInfo.processedSize = size(processedImage);
        return;
    end
    
    %% Resize Large Images
    if config.preprocessing.resize.enabled
        [h, w, ~] = size(processedImage);
        maxDim = config.preprocessing.resize.maxDimension;
        
        if h > maxDim || w > maxDim
            scaleFactor = maxDim / max(h, w);
            processedImage = imresize(processedImage, scaleFactor);
            preprocessInfo.steps{end+1} = sprintf('Resized by factor %.2f', scaleFactor);
            preprocessInfo.scaleFactor = scaleFactor;
            
            if config.processing.verbose
                fprintf('[PREPROCESSOR] Image resized from %dx%d to %dx%d\n', ...
                    w, h, size(processedImage, 2), size(processedImage, 1));
            end
        end
    end
    
    %% Store working copy
    workImage = processedImage;
    
    %% Contrast Enhancement (Adaptive Histogram Equalization)
    if config.preprocessing.contrastEnhancement.enabled
        try
            if channels == 3
                % Convert to LAB color space for luminance-only enhancement
                labImage = rgb2lab(workImage);
                L = labImage(:,:,1) / 100;  % Normalize to [0,1]
                
                % Apply CLAHE to luminance channel
                L = adapthisteq(L, ...
                    'ClipLimit', config.preprocessing.contrastEnhancement.clipLimit, ...
                    'NumTiles', config.preprocessing.contrastEnhancement.numTiles, ...
                    'Distribution', 'uniform');
                
                labImage(:,:,1) = L * 100;
                workImage = lab2rgb(labImage);
                workImage = im2uint8(workImage);
            else
                % Grayscale image
                workImage = adapthisteq(workImage, ...
                    'ClipLimit', config.preprocessing.contrastEnhancement.clipLimit, ...
                    'NumTiles', config.preprocessing.contrastEnhancement.numTiles, ...
                    'Distribution', 'uniform');
            end
            
            preprocessInfo.steps{end+1} = 'Contrast enhancement (CLAHE)';
            
            if config.processing.verbose
                fprintf('[PREPROCESSOR] Applied contrast enhancement (CLAHE)\n');
            end
        catch ME
            warning('PREPROCESSOR:ContrastError', 'Contrast enhancement failed: %s', ME.message);
        end
    end
    
    %% Denoising
    if config.preprocessing.denoising.enabled
        try
            filterSize = config.preprocessing.denoising.filterSize;
            
            switch lower(config.preprocessing.denoising.method)
                case 'gaussian'
                    sigma = filterSize / 3;
                    workImage = imgaussfilt(workImage, sigma);
                    preprocessInfo.steps{end+1} = sprintf('Gaussian denoising (sigma=%.2f)', sigma);
                    
                case 'median'
                    if channels == 3
                        for c = 1:3
                            workImage(:,:,c) = medfilt2(workImage(:,:,c), [filterSize, filterSize]);
                        end
                    else
                        workImage = medfilt2(workImage, [filterSize, filterSize]);
                    end
                    preprocessInfo.steps{end+1} = sprintf('Median filtering (%dx%d)', filterSize, filterSize);
                    
                otherwise
                    warning('PREPROCESSOR:UnknownMethod', 'Unknown denoising method: %s', ...
                        config.preprocessing.denoising.method);
            end
            
            if config.processing.verbose
                fprintf('[PREPROCESSOR] Applied %s denoising\n', config.preprocessing.denoising.method);
            end
        catch ME
            warning('PREPROCESSOR:DenoisingError', 'Denoising failed: %s', ME.message);
        end
    end
    
    %% Sharpening
    if config.preprocessing.sharpening.enabled
        try
            amount = config.preprocessing.sharpening.amount;
            workImage = imsharpen(workImage, 'Amount', amount);
            preprocessInfo.steps{end+1} = sprintf('Sharpening (amount=%.2f)', amount);
            
            if config.processing.verbose
                fprintf('[PREPROCESSOR] Applied sharpening (amount=%.2f)\n', amount);
            end
        catch ME
            warning('PREPROCESSOR:SharpeningError', 'Sharpening failed: %s', ME.message);
        end
    end
    
    %% Update Output
    processedImage = workImage;
    preprocessInfo.processedSize = size(processedImage);
    
    % Build enhancement summary string
    if ~isempty(preprocessInfo.steps)
        preprocessInfo.enhancementApplied = strjoin(preprocessInfo.steps, ', ');
    else
        preprocessInfo.enhancementApplied = 'None';
    end
    
    if config.processing.verbose
        fprintf('[PREPROCESSOR] Preprocessing complete. Steps: %s\n', preprocessInfo.enhancementApplied);
    end

end
