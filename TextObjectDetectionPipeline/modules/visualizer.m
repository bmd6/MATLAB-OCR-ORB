function visualizer(inputImage, results, config)
%VISUALIZER Generate visualization of detection results
%
%   VISUALIZER(INPUTIMAGE, RESULTS, CONFIG) creates a figure showing
%   the input image with bounding boxes around detected text and objects.
%
%   Inputs:
%       inputImage - Original input image
%       results    - Pipeline results structure containing:
%                    .textDetections   - Text detection results
%                    .objectDetections - Object detection results
%       config     - Configuration structure from default_config()
%
%   Visualization Features:
%       - Green bounding boxes for text detections
%       - Blue bounding boxes for object detections
%       - Labels with confidence/instance numbers
%       - Separate color crop display for objects (optional)
%
%   Example:
%       config = default_config();
%       visualizer(img, results, config);
%
%   See also: INSERTSHAPE, INSERTTEXT, FIGURE

    %% Input Validation
    if nargin < 3
        error('VISUALIZER:InvalidInput', 'inputImage, results, and config are required.');
    end
    
    if isempty(inputImage)
        warning('VISUALIZER:EmptyImage', 'Input image is empty. Cannot visualize.');
        return;
    end
    
    %% Prepare Image for Annotation
    % Ensure RGB for visualization
    if size(inputImage, 3) == 1
        displayImage = repmat(inputImage, [1, 1, 3]);
    else
        displayImage = inputImage;
    end
    
    % Convert to uint8 if needed
    if ~isa(displayImage, 'uint8')
        displayImage = im2uint8(displayImage);
    end
    
    %% Get Configuration
    textColor = config.visualization.textBoxColor;
    objectColor = config.visualization.objectBoxColor;
    lineWidth = config.visualization.lineWidth;
    fontSize = config.visualization.fontSize;
    showConfidence = config.visualization.showConfidence;
    showLabels = config.visualization.showLabels;
    figSize = config.visualization.figureSize;
    confidenceThreshold = config.ocr.confidenceThreshold;
    
    %% Draw Text Bounding Boxes
    textBoxes = [];
    textLabels = {};
    
    if ~isempty(results.textDetections)
        textIdx = 0;
        for i = 1:length(results.textDetections)
            td = results.textDetections(i);
            
            % Only show detections above threshold
            if td.confidence >= confidenceThreshold
                textIdx = textIdx + 1;
                bbox = td.boundingBox;
                textBoxes = [textBoxes; bbox];
                
                if showLabels
                    if showConfidence
                        label = sprintf('"%s" (%.0f%%)', td.text, td.confidence);
                    else
                        label = sprintf('"%s"', td.text);
                    end
                    textLabels{end+1} = label;
                end
            end
        end
    end
    
    % Draw text boxes
    if ~isempty(textBoxes)
        displayImage = insertShape(displayImage, 'Rectangle', textBoxes, ...
            'Color', textColor, 'LineWidth', lineWidth);
        
        if showLabels && ~isempty(textLabels)
            % Position labels above boxes
            labelPositions = [textBoxes(:,1), max(1, textBoxes(:,2) - 20)];
            displayImage = insertText(displayImage, labelPositions, textLabels, ...
                'FontSize', fontSize, 'TextColor', 'white', ...
                'BoxColor', textColor, 'BoxOpacity', 0.7);
        end
    end
    
    %% Draw Object Bounding Boxes
    objectBoxes = [];
    objectLabels = {};
    colorCrops = {};
    cropLabels = {};
    
    if ~isempty(results.objectDetections)
        for i = 1:length(results.objectDetections)
            od = results.objectDetections(i);
            refName = od.referenceName;
            
            for j = 1:length(od.instances)
                inst = od.instances(j);
                bbox = inst.boundingBox;
                objectBoxes = [objectBoxes; bbox];
                
                if showLabels
                    if showConfidence
                        label = sprintf('%s #%d (%.0f%%)', refName, j, inst.confidence * 100);
                    else
                        label = sprintf('%s #%d', refName, j);
                    end
                    objectLabels{end+1} = label;
                end
                
                % Store color crop for display
                if ~isempty(inst.colorCrop)
                    colorCrops{end+1} = inst.colorCrop;
                    cropLabels{end+1} = sprintf('%s #%d\nColor: [%d,%d,%d]', ...
                        refName, j, inst.dominantColor);
                end
            end
        end
    end
    
    % Draw object boxes
    if ~isempty(objectBoxes)
        displayImage = insertShape(displayImage, 'Rectangle', objectBoxes, ...
            'Color', objectColor, 'LineWidth', lineWidth);
        
        if showLabels && ~isempty(objectLabels)
            % Position labels above boxes
            labelPositions = [objectBoxes(:,1), max(1, objectBoxes(:,2) - 20)];
            displayImage = insertText(displayImage, labelPositions, objectLabels, ...
                'FontSize', fontSize, 'TextColor', 'white', ...
                'BoxColor', objectColor, 'BoxOpacity', 0.7);
        end
    end
    
    %% Create Figure
    fig = figure('Name', 'Detection Results', ...
        'NumberTitle', 'off', ...
        'Position', [100, 100, figSize(1), figSize(2)]);
    
    % Determine subplot layout based on what we have
    numColorCrops = length(colorCrops);
    
    if numColorCrops > 0 && numColorCrops <= 4
        % Show main image and color crops
        numSubplots = 1 + numColorCrops;
        
        if numSubplots <= 2
            rows = 1;
            cols = 2;
        elseif numSubplots <= 4
            rows = 2;
            cols = 2;
        else
            rows = 2;
            cols = 3;
        end
        
        % Main image
        subplot(rows, cols, 1);
        imshow(displayImage);
        title(sprintf('Detection Results\nText: %d (green) | Objects: %d (blue)', ...
            size(textBoxes, 1), size(objectBoxes, 1)), 'FontSize', 12);
        
        % Color crops
        for i = 1:min(numColorCrops, rows*cols - 1)
            subplot(rows, cols, i + 1);
            imshow(colorCrops{i});
            title(cropLabels{i}, 'FontSize', 10);
        end
        
    else
        % Just show main image
        imshow(displayImage);
        title(sprintf('Detection Results\nText Detections: %d (green) | Object Detections: %d (blue)', ...
            size(textBoxes, 1), size(objectBoxes, 1)), 'FontSize', 14);
    end
    
    %% Add Legend/Info Box
    % Create a text annotation with summary info
    numTextDetected = size(textBoxes, 1);
    numObjectsDetected = size(objectBoxes, 1);
    
    summaryStr = sprintf(['Detection Summary:\n' ...
        '• Text regions: %d (threshold: %.0f%%)\n' ...
        '• Object instances: %d\n' ...
        '• Text accuracy: %.1f%%\n' ...
        '• Object accuracy: %.1f%%\n' ...
        '• Overall accuracy: %.1f%%'], ...
        numTextDetected, confidenceThreshold, ...
        numObjectsDetected, ...
        results.accuracy.textAccuracy * 100, ...
        results.accuracy.objectAccuracy * 100, ...
        results.accuracy.overallAccuracy * 100);
    
    % Add annotation
    annotation(fig, 'textbox', [0.01, 0.01, 0.25, 0.15], ...
        'String', summaryStr, ...
        'FontSize', 9, ...
        'BackgroundColor', [0.95, 0.95, 0.95], ...
        'EdgeColor', [0.5, 0.5, 0.5], ...
        'FitBoxToText', 'on');
    
    %% Add Color Legend
    % Create a small legend in the corner
    hold on;
    
    % This is a workaround since we're using insertShape instead of plot
    % The legend info is included in the annotation above
    
    hold off;
    
    if config.processing.verbose
        fprintf('[VISUALIZER] Figure created with %d text and %d object detections.\n', ...
            numTextDetected, numObjectsDetected);
    end

end
