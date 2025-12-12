function accuracy = accuracy_calculator(results, referenceText, config)
%ACCURACY_CALCULATOR Calculate accuracy metrics for detection results
%
%   ACCURACY = ACCURACY_CALCULATOR(RESULTS, REFERENCETEXT, CONFIG)
%   computes accuracy metrics based on detection confidence and match quality.
%
%   Inputs:
%       results       - Pipeline results structure containing:
%                       .textDetections   - Text detection results
%                       .objectDetections - Object detection results
%       referenceText - Cell array of expected text strings
%       config        - Configuration structure from default_config()
%
%   Outputs:
%       accuracy - Structure containing:
%                  .textAccuracy       - Text detection accuracy (0-1)
%                  .objectAccuracy     - Object detection accuracy (0-1)
%                  .overallAccuracy    - Weighted combined accuracy (0-1)
%                  .textDetails        - Detailed text metrics
%                  .objectDetails      - Detailed object metrics
%
%   Accuracy Metrics:
%       Text Detection:
%           - Average confidence of detections above threshold
%           - Reference match rate (if reference text provided)
%           - Levenshtein similarity for matched text
%
%       Object Detection:
%           - Feature match ratio (matched/total reference features)
%           - Geometric consistency score (RANSAC inlier ratio)
%           - Combined weighted score
%
%   Example:
%       config = default_config();
%       accuracy = accuracy_calculator(results, refText, config);
%
%   See also: TEXT_DETECTOR, OBJECT_DETECTOR

    %% Initialize Output Structure
    accuracy = struct();
    accuracy.textAccuracy = 0;
    accuracy.objectAccuracy = 0;
    accuracy.overallAccuracy = 0;
    accuracy.textDetails = struct();
    accuracy.objectDetails = struct();
    
    %% Calculate Text Detection Accuracy
    textDetails = struct();
    textDetails.numDetections = 0;
    textDetails.numAboveThreshold = 0;
    textDetails.averageConfidence = 0;
    textDetails.numMatchedToReference = 0;
    textDetails.averageSimilarity = 0;
    textDetails.referenceMatchRate = 0;
    
    if ~isempty(results.textDetections)
        textDetections = results.textDetections;
        numDetections = length(textDetections);
        textDetails.numDetections = numDetections;
        
        % Filter by confidence threshold
        confidences = [textDetections.confidence];
        aboveThreshold = confidences >= config.ocr.confidenceThreshold;
        numAboveThreshold = sum(aboveThreshold);
        textDetails.numAboveThreshold = numAboveThreshold;
        
        if numAboveThreshold > 0
            % Average confidence of valid detections
            validConfidences = confidences(aboveThreshold);
            textDetails.averageConfidence = mean(validConfidences) / 100;  % Normalize to 0-1
            
            % Check for reference matches
            if ~isempty(referenceText)
                similarities = zeros(numAboveThreshold, 1);
                matchedCount = 0;
                validIdx = find(aboveThreshold);
                
                for i = 1:numAboveThreshold
                    idx = validIdx(i);
                    if isfield(textDetections(idx), 'matchedReference') && ...
                       ~isempty(textDetections(idx).matchedReference)
                        matchedCount = matchedCount + 1;
                        similarities(i) = textDetections(idx).similarity;
                    end
                end
                
                textDetails.numMatchedToReference = matchedCount;
                
                if matchedCount > 0
                    textDetails.averageSimilarity = mean(similarities(similarities > 0));
                end
                
                % Reference match rate: how many reference texts were found
                textDetails.referenceMatchRate = matchedCount / length(referenceText);
            end
            
            % Combined text accuracy
            % Weight: 60% confidence, 40% reference matching
            if ~isempty(referenceText) && textDetails.numMatchedToReference > 0
                accuracy.textAccuracy = 0.6 * textDetails.averageConfidence + ...
                                       0.4 * textDetails.averageSimilarity;
            else
                accuracy.textAccuracy = textDetails.averageConfidence;
            end
        end
    end
    
    accuracy.textDetails = textDetails;
    
    %% Calculate Object Detection Accuracy
    objectDetails = struct();
    objectDetails.numReferencesMatched = 0;
    objectDetails.totalInstances = 0;
    objectDetails.averageConfidence = 0;
    objectDetails.averageInlierRatio = 0;
    objectDetails.averageMatchedFeatures = 0;
    objectDetails.perReferenceDetails = struct('name', {}, 'numInstances', {}, ...
        'avgConfidence', {}, 'avgInlierRatio', {});
    
    if ~isempty(results.objectDetections)
        objectDetections = results.objectDetections;
        numRefs = length(objectDetections);
        objectDetails.numReferencesMatched = numRefs;
        
        allConfidences = [];
        allInlierRatios = [];
        allMatchedFeatures = [];
        
        for i = 1:numRefs
            refName = objectDetections(i).referenceName;
            instances = objectDetections(i).instances;
            numInstances = length(instances);
            
            objectDetails.totalInstances = objectDetails.totalInstances + numInstances;
            
            if numInstances > 0
                instanceConfidences = [instances.confidence];
                instanceInlierRatios = [instances.inlierRatio];
                instanceMatchedFeatures = [instances.matchedFeatures];
                
                allConfidences = [allConfidences, instanceConfidences];
                allInlierRatios = [allInlierRatios, instanceInlierRatios];
                allMatchedFeatures = [allMatchedFeatures, instanceMatchedFeatures];
                
                % Per-reference details
                refDetail = struct();
                refDetail.name = refName;
                refDetail.numInstances = numInstances;
                refDetail.avgConfidence = mean(instanceConfidences);
                refDetail.avgInlierRatio = mean(instanceInlierRatios);
                
                objectDetails.perReferenceDetails(end+1) = refDetail;
            end
        end
        
        if objectDetails.totalInstances > 0
            objectDetails.averageConfidence = mean(allConfidences);
            objectDetails.averageInlierRatio = mean(allInlierRatios);
            objectDetails.averageMatchedFeatures = mean(allMatchedFeatures);
            
            % Combined object accuracy
            % Weight: 50% feature match confidence, 50% geometric consistency (inlier ratio)
            accuracy.objectAccuracy = 0.5 * objectDetails.averageConfidence + ...
                                     0.5 * objectDetails.averageInlierRatio;
        end
    end
    
    accuracy.objectDetails = objectDetails;
    
    %% Calculate Overall Accuracy
    % Weighted combination of text and object accuracy
    textWeight = config.accuracy.textWeight;
    objectWeight = config.accuracy.objectWeight;
    
    % Normalize weights
    totalWeight = textWeight + objectWeight;
    textWeight = textWeight / totalWeight;
    objectWeight = objectWeight / totalWeight;
    
    % Handle cases where one type has no detections
    if accuracy.textAccuracy == 0 && accuracy.objectAccuracy > 0
        accuracy.overallAccuracy = accuracy.objectAccuracy;
    elseif accuracy.objectAccuracy == 0 && accuracy.textAccuracy > 0
        accuracy.overallAccuracy = accuracy.textAccuracy;
    elseif accuracy.textAccuracy == 0 && accuracy.objectAccuracy == 0
        accuracy.overallAccuracy = 0;
    else
        accuracy.overallAccuracy = textWeight * accuracy.textAccuracy + ...
                                  objectWeight * accuracy.objectAccuracy;
    end
    
    %% Print Detailed Metrics (if verbose)
    if config.processing.verbose
        fprintf('\n[ACCURACY_CALCULATOR] Detailed Metrics:\n');
        fprintf('  --- Text Detection ---\n');
        fprintf('    Total detections: %d\n', textDetails.numDetections);
        fprintf('    Above threshold:  %d\n', textDetails.numAboveThreshold);
        fprintf('    Avg confidence:   %.2f%%\n', textDetails.averageConfidence * 100);
        if ~isempty(referenceText)
            fprintf('    Matched to ref:   %d/%d\n', textDetails.numMatchedToReference, length(referenceText));
            fprintf('    Avg similarity:   %.2f%%\n', textDetails.averageSimilarity * 100);
        end
        fprintf('    Text accuracy:    %.2f%%\n', accuracy.textAccuracy * 100);
        
        fprintf('  --- Object Detection ---\n');
        fprintf('    References matched: %d\n', objectDetails.numReferencesMatched);
        fprintf('    Total instances:    %d\n', objectDetails.totalInstances);
        fprintf('    Avg confidence:     %.2f%%\n', objectDetails.averageConfidence * 100);
        fprintf('    Avg inlier ratio:   %.2f%%\n', objectDetails.averageInlierRatio * 100);
        fprintf('    Avg matched feats:  %.1f\n', objectDetails.averageMatchedFeatures);
        fprintf('    Object accuracy:    %.2f%%\n', accuracy.objectAccuracy * 100);
        
        fprintf('  --- Overall ---\n');
        fprintf('    Combined accuracy:  %.2f%%\n', accuracy.overallAccuracy * 100);
    end

end
