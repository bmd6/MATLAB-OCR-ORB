function [textDetections, textRegions] = text_detector(processedImage, originalImage, referenceText, config, roi, useROI)
%TEXT_DETECTOR Detect and extract text using OCR (Tesseract)
%
%   [TEXTDETECTIONS, TEXTREGIONS] = TEXT_DETECTOR(PROCESSEDIMAGE, ORIGINALIMAGE, ...
%       REFERENCETEXT, CONFIG, ROI, USEROI)
%   performs optical character recognition on the input image.
%
%   Inputs:
%       processedImage - Preprocessed image for OCR
%       originalImage  - Original image (for coordinate mapping if ROI used)
%       referenceText  - Cell array of expected text strings for comparison
%       config         - Configuration structure from default_config()
%       roi            - Region of interest [x, y, width, height] (optional)
%       useROI         - Boolean flag indicating ROI usage (optional)
%
%   Outputs:
%       textDetections - Structure array with fields:
%                        .text          - Detected text string
%                        .confidence    - OCR confidence (0-100)
%                        .boundingBox   - [x, y, width, height] in original image
%                        .matchedReference - Matched reference text (if any)
%                        .similarity    - Similarity score to reference (0-1)
%       textRegions    - Binary mask of text regions
%
%   Example:
%       config = default_config();
%       [detections, regions] = text_detector(img, img, refText, config, [], false);
%
%   See also: OCR, OCRTEXT, LEVENSHTEIN_DISTANCE

    %% Input Validation
    if nargin < 4
        error('TEXT_DETECTOR:InvalidInput', 'At least processedImage, originalImage, referenceText, and config are required.');
    end
    
    if nargin < 5 || isempty(roi)
        roi = [];
    end
    
    if nargin < 6
        useROI = false;
    end
    
    %% Initialize Outputs
    textDetections = struct('text', {}, 'confidence', {}, 'boundingBox', {}, ...
        'matchedReference', {}, 'similarity', {});
    
    [h, w, ~] = size(processedImage);
    textRegions = false(h, w);
    
    %% Prepare Image for OCR
    % Convert to grayscale if needed (OCR often works better on grayscale)
    if size(processedImage, 3) == 3
        grayImage = rgb2gray(processedImage);
    else
        grayImage = processedImage;
    end
    
    % Additional preprocessing for better OCR results
    % Binarize using adaptive thresholding
    try
        % Use Otsu's method or adaptive threshold
        binaryImage = imbinarize(grayImage, 'adaptive', 'ForegroundPolarity', 'dark', 'Sensitivity', 0.4);
    catch
        binaryImage = grayImage;
    end
    
    %% Perform OCR
    try
        % Set OCR parameters based on config
        ocrParams = {'Language', config.ocr.language};
        
        % Add character set if specified
        if ~isempty(config.ocr.characterSet)
            ocrParams = [ocrParams, {'CharacterSet', config.ocr.characterSet}];
        end
        
        % Set layout analysis mode (MATLAB R2024b uses 'LayoutAnalysis' instead of 'TextLayout')
        % Note: 'LayoutAnalysis' replaces deprecated 'TextLayout' parameter
        ocrParams = [ocrParams, {'LayoutAnalysis', config.ocr.layoutAnalysis}];
        
        % Perform OCR on the grayscale image
        ocrResults = ocr(grayImage, ocrParams{:});
        
        if config.processing.verbose
            fprintf('[TEXT_DETECTOR] OCR completed. Found %d text regions.\n', ...
                length(ocrResults.Words));
        end
        
    catch ME
        warning('TEXT_DETECTOR:OCRError', 'OCR failed: %s', ME.message);
        return;
    end
    
    %% Process OCR Results
    if isempty(ocrResults.Words)
        if config.processing.verbose
            fprintf('[TEXT_DETECTOR] No text detected in image.\n');
        end
        return;
    end
    
    % Get word-level results with bounding boxes
    words = ocrResults.Words;
    wordConfidences = ocrResults.WordConfidences;
    wordBBoxes = ocrResults.WordBoundingBoxes;
    
    % Filter by confidence threshold (but store all for analysis)
    numWords = length(words);
    
    for i = 1:numWords
        if isempty(words{i}) || isempty(strtrim(words{i}))
            continue;
        end
        
        % Get confidence (convert to percentage if needed)
        confidence = wordConfidences(i);
        if confidence <= 1
            confidence = confidence * 100;
        end
        
        % Get bounding box [x, y, width, height]
        bbox = wordBBoxes(i, :);
        
        % Adjust bounding box if ROI was used
        if useROI && ~isempty(roi)
            bbox(1) = bbox(1) + roi(1) - 1;
            bbox(2) = bbox(2) + roi(2) - 1;
        end
        
        % Create detection entry
        detection = struct();
        detection.text = strtrim(words{i});
        detection.confidence = confidence;
        detection.boundingBox = bbox;
        detection.matchedReference = '';
        detection.similarity = 0;
        
        % Match against reference text if provided
        if ~isempty(referenceText) && confidence >= config.ocr.confidenceThreshold
            [matchedRef, similarity] = match_text_to_reference(detection.text, referenceText, config);
            detection.matchedReference = matchedRef;
            detection.similarity = similarity;
        end
        
        % Add to detections
        textDetections(end+1) = detection;
        
        % Update text regions mask (for region exclusion)
        if confidence >= config.ocr.confidenceThreshold
            % Create region mask for this detection
            x1 = max(1, round(bbox(1)));
            y1 = max(1, round(bbox(2)));
            x2 = min(w, round(bbox(1) + bbox(3)));
            y2 = min(h, round(bbox(2) + bbox(4)));
            
            if x2 > x1 && y2 > y1
                textRegions(y1:y2, x1:x2) = true;
            end
        end
    end
    
    %% Also try to detect text at line/block level for better context
    try
        % Get line-level text for context
        lineText = ocrResults.Text;
        if ~isempty(lineText) && config.processing.verbose
            fprintf('[TEXT_DETECTOR] Full text detected:\n%s\n', lineText);
        end
    catch
        % Line detection not critical
    end
    
    %% Summary
    validDetections = sum([textDetections.confidence] >= config.ocr.confidenceThreshold);
    if config.processing.verbose
        fprintf('[TEXT_DETECTOR] %d/%d detections above confidence threshold (%.0f%%)\n', ...
            validDetections, length(textDetections), config.ocr.confidenceThreshold);
    end

end

%% Helper Function: Match Text to Reference
function [matchedRef, similarity] = match_text_to_reference(detectedText, referenceText, config)
%MATCH_TEXT_TO_REFERENCE Find best matching reference text
%
%   Uses Levenshtein distance (edit distance) to find the closest match

    matchedRef = '';
    similarity = 0;
    
    if isempty(detectedText) || isempty(referenceText)
        return;
    end
    
    % Normalize detected text (case-insensitive comparison)
    detectedNorm = lower(strtrim(detectedText));
    
    bestSimilarity = 0;
    bestMatch = '';
    
    for i = 1:length(referenceText)
        refNorm = lower(strtrim(referenceText{i}));
        
        if isempty(refNorm)
            continue;
        end
        
        % Calculate Levenshtein distance
        distance = levenshtein_distance(detectedNorm, refNorm);
        maxLen = max(length(detectedNorm), length(refNorm));
        
        if maxLen == 0
            continue;
        end
        
        % Calculate similarity (1 - normalized distance)
        sim = 1 - (distance / maxLen);
        
        % Check for exact match (ignoring case)
        if strcmp(detectedNorm, refNorm)
            sim = 1.0;
        end
        
        if sim > bestSimilarity
            bestSimilarity = sim;
            bestMatch = referenceText{i};
        end
    end
    
    % Only return match if above threshold
    if bestSimilarity >= config.accuracy.textMatchThreshold
        matchedRef = bestMatch;
        similarity = bestSimilarity;
    end

end

%% Helper Function: Levenshtein Distance
function distance = levenshtein_distance(s1, s2)
%LEVENSHTEIN_DISTANCE Calculate edit distance between two strings

    m = length(s1);
    n = length(s2);
    
    % Create distance matrix
    D = zeros(m+1, n+1);
    
    % Initialize first column and row
    D(:, 1) = (0:m)';
    D(1, :) = 0:n;
    
    % Fill in the rest of the matrix
    for i = 2:(m+1)
        for j = 2:(n+1)
            if s1(i-1) == s2(j-1)
                cost = 0;
            else
                cost = 1;
            end
            
            D(i, j) = min([D(i-1, j) + 1, ...      % Deletion
                          D(i, j-1) + 1, ...      % Insertion
                          D(i-1, j-1) + cost]);   % Substitution
        end
    end
    
    distance = D(m+1, n+1);

end
