function [objectDetections, objectRegions] = object_detector(processedImage, originalImage, referenceImages, config, excludedRegions, roi, useROI)
%OBJECT_DETECTOR Detect objects using ORB feature matching
%
%   [OBJECTDETECTIONS, OBJECTREGIONS] = OBJECT_DETECTOR(PROCESSEDIMAGE, ...
%       ORIGINALIMAGE, REFERENCEIMAGES, CONFIG, EXCLUDEDREGIONS, ROI, USEROI)
%   detects reference objects in the input image using ORB features.
%
%   Inputs:
%       processedImage  - Preprocessed image for detection
%       originalImage   - Original color image (for color extraction)
%       referenceImages - Structure array of reference images (from load_reference_data)
%       config          - Configuration structure from default_config()
%       excludedRegions - Nx4 matrix of regions to exclude [x, y, w, h] per row
%       roi             - Region of interest [x, y, width, height] (optional)
%       useROI          - Boolean flag indicating ROI usage (optional)
%
%   Outputs:
%       objectDetections - Structure array with fields:
%                          .referenceName - Name of matched reference
%                          .instances     - Array of detected instances
%       objectRegions    - Binary mask of object regions
%
%   Each instance contains:
%       .boundingBox     - [x, y, width, height] in original image
%       .confidence      - Match confidence (feature match ratio)
%       .matchedFeatures - Number of matched features
%       .inlierRatio     - RANSAC inlier ratio
%       .dominantColor   - [R, G, B] dominant color
%       .colorCrop       - Full color crop of the region
%       .homography      - Transformation matrix
%
%   Example:
%       config = default_config();
%       [detections, regions] = object_detector(img, img, refImages, config, [], [], false);
%
%   See also: DETECTORBFEATURES, EXTRACTFEATURES, MATCHFEATURES, ESTIMATEGEOMETRICTRANSFORM2D

    %% Input Validation
    if nargin < 4
        error('OBJECT_DETECTOR:InvalidInput', 'At least processedImage, originalImage, referenceImages, and config are required.');
    end
    
    if nargin < 5 || isempty(excludedRegions)
        excludedRegions = [];
    end
    
    if nargin < 6 || isempty(roi)
        roi = [];
    end
    
    if nargin < 7
        useROI = false;
    end
    
    %% Initialize Outputs
    objectDetections = struct('referenceName', {}, 'instances', {});
    
    [h, w, ~] = size(processedImage);
    objectRegions = false(h, w);
    
    %% Validate Reference Images
    if isempty(referenceImages)
        if config.processing.verbose
            fprintf('[OBJECT_DETECTOR] No reference images provided.\n');
        end
        return;
    end
    
    %% Convert Input Image to Grayscale
    if size(processedImage, 3) == 3
        grayInput = rgb2gray(processedImage);
    else
        grayInput = processedImage;
    end
    
    %% Detect ORB Features in Input Image
    try
        inputPoints = detectORBFeatures(grayInput, ...
            'NumLevels', 8, ...
            'ScaleFactor', 1.2);
        
        if isempty(inputPoints) || inputPoints.Count == 0
            if config.processing.verbose
                fprintf('[OBJECT_DETECTOR] No ORB features detected in input image.\n');
            end
            return;
        end
        
        % Limit features
        if inputPoints.Count > config.orb.maxFeatures
            inputPoints = inputPoints.selectStrongest(config.orb.maxFeatures);
        end
        
        [inputFeatures, inputPoints] = extractFeatures(grayInput, inputPoints);
        
        if config.processing.verbose
            fprintf('[OBJECT_DETECTOR] Detected %d ORB features in input image.\n', inputPoints.Count);
        end
        
    catch ME
        warning('OBJECT_DETECTOR:FeatureError', 'Failed to detect features: %s', ME.message);
        return;
    end
    
    %% Create Exclusion Mask
    exclusionMask = false(h, w);
    if ~isempty(excludedRegions)
        padding = config.exclusion.padding;
        for i = 1:size(excludedRegions, 1)
            bbox = excludedRegions(i, :);
            x1 = max(1, round(bbox(1)) - padding);
            y1 = max(1, round(bbox(2)) - padding);
            x2 = min(w, round(bbox(1) + bbox(3)) + padding);
            y2 = min(h, round(bbox(2) + bbox(4)) + padding);
            
            if x2 > x1 && y2 > y1
                exclusionMask(y1:y2, x1:x2) = true;
            end
        end
        
        if config.processing.verbose
            fprintf('[OBJECT_DETECTOR] Created exclusion mask for %d regions.\n', size(excludedRegions, 1));
        end
    end
    
    %% Track All Detected Bounding Boxes for NMS
    allDetectedBBoxes = [];
    
    %% Process Each Reference Image
    numRefs = length(referenceImages);
    refResults = cell(numRefs, 1);
    
    for refIdx = 1:numRefs
        refImg = referenceImages(refIdx);
        refName = refImg.name;
        refResults{refIdx} = struct('instances', []);
        
        if config.processing.verbose
            fprintf('[OBJECT_DETECTOR] Matching against reference: %s\n', refName);
        end
        
        %% Get Reference Features
        if config.processing.cacheFeatures && ~isempty(refImg.features)
            refFeatures = refImg.features;
            refPoints = refImg.points;
        else
            try
                refPoints = detectORBFeatures(refImg.gray, 'NumLevels', 8, 'ScaleFactor', 1.2);
                
                if isempty(refPoints) || refPoints.Count == 0
                    if config.processing.verbose
                        fprintf('[OBJECT_DETECTOR]   No features in reference %s, skipping.\n', refName);
                    end
                    continue;
                end
                
                if refPoints.Count > config.orb.maxFeatures
                    refPoints = refPoints.selectStrongest(config.orb.maxFeatures);
                end
                
                [refFeatures, refPoints] = extractFeatures(refImg.gray, refPoints);
            catch ME
                warning('OBJECT_DETECTOR:RefFeatureError', ...
                    'Failed to extract features from reference %s: %s', refName, ME.message);
                continue;
            end
        end
        
        if isempty(refFeatures)
            continue;
        end
        
        [refH, refW] = size(refImg.gray);
        
        %% Match Features
        try
            indexPairs = matchFeatures(refFeatures, inputFeatures, ...
                'Method', 'Approximate', ...
                'MatchThreshold', 100, ...
                'MaxRatio', config.orb.matchRatioThreshold, ...
                'Unique', true);
            
            numMatches = size(indexPairs, 1);
            
            if numMatches < config.orb.minMatchedFeatures
                if config.processing.verbose
                    fprintf('[OBJECT_DETECTOR]   Insufficient matches (%d < %d) for %s\n', ...
                        numMatches, config.orb.minMatchedFeatures, refName);
                end
                continue;
            end
            
            if config.processing.verbose
                fprintf('[OBJECT_DETECTOR]   Found %d feature matches for %s\n', numMatches, refName);
            end
            
        catch ME
            warning('OBJECT_DETECTOR:MatchError', 'Feature matching failed: %s', ME.message);
            continue;
        end
        
        %% Get Matched Points
        matchedRefPoints = refPoints(indexPairs(:, 1));
        matchedInputPoints = inputPoints(indexPairs(:, 2));
        
        %% Find Multiple Instances using Iterative RANSAC
        usedInputPoints = false(numMatches, 1);
        instanceCount = 0;
        instances = struct('boundingBox', {}, 'confidence', {}, 'matchedFeatures', {}, ...
            'inlierRatio', {}, 'dominantColor', {}, 'colorCrop', {}, 'homography', {});
        
        while instanceCount < config.orb.maxInstancesPerReference
            %% Find Available Matches
            availableIdx = find(~usedInputPoints);
            
            if length(availableIdx) < config.orb.minMatchedFeatures
                break;
            end
            
            %% RANSAC Geometric Verification
            try
                availableRefLocs = matchedRefPoints.Location(availableIdx, :);
                availableInputLocs = matchedInputPoints.Location(availableIdx, :);
                
                [tform, inlierIdx] = estimateGeometricTransform2D(...
                    availableRefLocs, ...
                    availableInputLocs, ...
                    'projective', ...
                    'MaxDistance', config.orb.ransac.threshold, ...
                    'Confidence', config.orb.ransac.confidence * 100, ...
                    'MaxNumTrials', config.orb.ransac.maxIterations);
                
                numInliers = sum(inlierIdx);
                inlierRatio = numInliers / length(availableIdx);
                
                if numInliers < config.orb.minMatchedFeatures || inlierRatio < config.orb.minInlierRatio
                    break;
                end
                
            catch
                break;
            end
            
            %% Compute Bounding Box by Transforming Reference Corners
            refCorners = [1, 1; refW, 1; refW, refH; 1, refH];
            
            try
                transformedCorners = transformPointsForward(tform, refCorners);
            catch
                break;
            end
            
            minX = min(transformedCorners(:, 1));
            maxX = max(transformedCorners(:, 1));
            minY = min(transformedCorners(:, 2));
            maxY = max(transformedCorners(:, 2));
            
            bbox = [minX, minY, maxX - minX, maxY - minY];
            
            %% Validate Bounding Box
            if bbox(1) < 1 - bbox(3) || bbox(2) < 1 - bbox(4) || ...
               bbox(1) > w || bbox(2) > h || ...
               bbox(3) < 10 || bbox(4) < 10 || ...
               bbox(3) > w * 2 || bbox(4) > h * 2
                usedInputPoints(availableIdx(inlierIdx)) = true;
                continue;
            end
            
            x1 = max(1, round(bbox(1)));
            y1 = max(1, round(bbox(2)));
            x2 = min(w, round(bbox(1) + bbox(3)));
            y2 = min(h, round(bbox(2) + bbox(4)));
            
            if x2 <= x1 || y2 <= y1
                usedInputPoints(availableIdx(inlierIdx)) = true;
                continue;
            end
            
            bbox = [x1, y1, x2 - x1, y2 - y1];
            
            %% Check Against Exclusion Mask
            bboxMask = false(h, w);
            bboxMask(y1:y2, x1:x2) = true;
            overlapWithExcluded = sum(bboxMask(:) & exclusionMask(:)) / sum(bboxMask(:));
            
            if overlapWithExcluded > config.exclusion.overlapThreshold
                usedInputPoints(availableIdx(inlierIdx)) = true;
                continue;
            end
            
            %% Extract Color Information from Original Image
            try
                if size(originalImage, 3) == 3
                    colorCrop = originalImage(y1:y2, x1:x2, :);
                else
                    colorCrop = repmat(originalImage(y1:y2, x1:x2), [1, 1, 3]);
                end
                
                dominantColor = calculate_dominant_color(colorCrop);
            catch
                colorCrop = [];
                dominantColor = [0, 0, 0];
            end
            
            %% Calculate Confidence
            confidence = numInliers / size(refFeatures, 1);
            
            %% Store Instance
            instanceCount = instanceCount + 1;
            inst = struct();
            inst.boundingBox = bbox;
            inst.confidence = confidence;
            inst.matchedFeatures = numInliers;
            inst.inlierRatio = inlierRatio;
            inst.dominantColor = dominantColor;
            inst.colorCrop = colorCrop;
            inst.homography = tform.T;
            
            instances(end+1) = inst;
            
            usedInputPoints(availableIdx(inlierIdx)) = true;
            objectRegions(y1:y2, x1:x2) = true;
            allDetectedBBoxes = [allDetectedBBoxes; bbox, confidence, refIdx];
            
            if config.processing.verbose
                fprintf('[OBJECT_DETECTOR]   Instance %d: bbox=[%.0f, %.0f, %.0f, %.0f], conf=%.2f, inliers=%d\n', ...
                    instanceCount, bbox, confidence, numInliers);
            end
        end
        
        refResults{refIdx}.instances = instances;
    end
    
    %% Apply Non-Maximum Suppression
    if ~isempty(allDetectedBBoxes) && size(allDetectedBBoxes, 1) > 1
        keepIdx = nms_boxes(allDetectedBBoxes(:, 1:4), allDetectedBBoxes(:, 5), ...
            config.orb.nmsOverlapThreshold);
        
        if config.processing.verbose
            fprintf('[OBJECT_DETECTOR] NMS: kept %d/%d detections\n', ...
                length(keepIdx), size(allDetectedBBoxes, 1));
        end
    end
    
    %% Build Final Output Structure
    for refIdx = 1:numRefs
        refImg = referenceImages(refIdx);
        refName = refImg.name;
        
        if ~isempty(refResults{refIdx}.instances)
            detection = struct();
            detection.referenceName = refName;
            detection.instances = refResults{refIdx}.instances;
            objectDetections(end+1) = detection;
        end
    end
    
    %% Summary
    totalInstances = 0;
    for i = 1:length(objectDetections)
        totalInstances = totalInstances + length(objectDetections(i).instances);
    end
    
    if config.processing.verbose
        fprintf('[OBJECT_DETECTOR] Total: %d object instances detected from %d references.\n', ...
            totalInstances, length(objectDetections));
    end

end

%% Helper Function: Calculate Dominant Color
function dominantColor = calculate_dominant_color(colorCrop)
    if isempty(colorCrop)
        dominantColor = [0, 0, 0];
        return;
    end
    
    [~, ~, c] = size(colorCrop);
    
    if c < 3
        avgVal = mean(colorCrop(:));
        dominantColor = [avgVal, avgVal, avgVal];
        return;
    end
    
    pixels = reshape(double(colorCrop), [], 3);
    
    try
        if size(pixels, 1) > 100
            sampleIdx = randperm(size(pixels, 1), min(1000, size(pixels, 1)));
            samplePixels = pixels(sampleIdx, :);
            
            [~, centroids] = kmeans(samplePixels, 3, 'MaxIter', 50, 'Replicates', 1);
            
            distances = pdist2(samplePixels, centroids);
            [~, assignments] = min(distances, [], 2);
            counts = histcounts(assignments, 1:4);
            [~, dominantIdx] = max(counts);
            
            dominantColor = round(centroids(dominantIdx, :));
        else
            dominantColor = round(mean(pixels, 1));
        end
    catch
        dominantColor = round(mean(pixels, 1));
    end
    
    dominantColor = max(0, min(255, dominantColor));
end

%% Helper Function: Non-Maximum Suppression
function keepIdx = nms_boxes(boxes, scores, overlapThresh)
    if isempty(boxes)
        keepIdx = [];
        return;
    end
    
    x1 = boxes(:, 1);
    y1 = boxes(:, 2);
    x2 = boxes(:, 1) + boxes(:, 3);
    y2 = boxes(:, 2) + boxes(:, 4);
    
    areas = (x2 - x1) .* (y2 - y1);
    [~, sortIdx] = sort(scores, 'descend');
    keepIdx = [];
    
    while ~isempty(sortIdx)
        i = sortIdx(1);
        keepIdx = [keepIdx; i];
        
        if length(sortIdx) == 1
            break;
        end
        
        remaining = sortIdx(2:end);
        
        xx1 = max(x1(i), x1(remaining));
        yy1 = max(y1(i), y1(remaining));
        xx2 = min(x2(i), x2(remaining));
        yy2 = min(y2(i), y2(remaining));
        
        interWidth = max(0, xx2 - xx1);
        interHeight = max(0, yy2 - yy1);
        interArea = interWidth .* interHeight;
        
        iou = interArea ./ (areas(i) + areas(remaining) - interArea);
        sortIdx = remaining(iou < overlapThresh);
    end
end
