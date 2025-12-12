%% MAIN_PIPELINE - Text and Object Detection Pipeline
% Main entry point for the text identification, extraction, and object
% detection pipeline using OCR (Tesseract) and ORB feature matching.
%
% This script orchestrates the entire detection pipeline:
%   1. Loads and validates input image and reference data
%   2. Preprocesses images based on configuration
%   3. Performs text detection using OCR (Tesseract)
%   4. Performs object detection using ORB features
%   5. Calculates accuracy metrics
%   6. Visualizes results with bounding boxes
%
% Usage:
%   Run this script and follow the prompts to select:
%   - Input image file
%   - Reference images directory (containing reference_text.txt)
%
% Optional: Modify config/default_config.m to adjust parameters
%
% Author: Generated for MATLAB R2024b
% Date: 2024
% Version: 1.0.0
%
% See also: DEFAULT_CONFIG, IMAGE_LOADER, TEXT_DETECTOR, OBJECT_DETECTOR

%% Initialization
clear; clc; close all;

% Add module paths
scriptDir = fileparts(mfilename('fullpath'));
addpath(fullfile(scriptDir, 'config'));
addpath(fullfile(scriptDir, 'modules'));
addpath(fullfile(scriptDir, 'utils'));

fprintf('==========================================================\n');
fprintf('   Text and Object Detection Pipeline v1.0.0\n');
fprintf('   MATLAB R2024b - OCR (Tesseract) + ORB Detection\n');
fprintf('==========================================================\n\n');

%% Load Configuration
try
    config = default_config();
    fprintf('[INFO] Configuration loaded successfully.\n');
catch ME
    fprintf('[ERROR] Failed to load configuration: %s\n', ME.message);
    return;
end

%% User Input: Select Input Image
fprintf('\n--- Input Image Selection ---\n');
[inputFileName, inputFilePath] = uigetfile(...
    {'*.png;*.jpg;*.jpeg;*.bmp;*.tiff;*.tif;*.gif', 'Image Files (*.png, *.jpg, *.bmp, *.tiff, *.gif)'; ...
     '*.*', 'All Files (*.*)'}, ...
    'Select Input Image');

if isequal(inputFileName, 0)
    fprintf('[INFO] User cancelled input image selection. Exiting.\n');
    return;
end

inputImagePath = fullfile(inputFilePath, inputFileName);
fprintf('[INFO] Selected input image: %s\n', inputImagePath);

%% User Input: Select Reference Images Directory
fprintf('\n--- Reference Directory Selection ---\n');
referenceDir = uigetdir(pwd, 'Select Reference Images Directory');

if isequal(referenceDir, 0)
    fprintf('[INFO] User cancelled reference directory selection. Exiting.\n');
    return;
end

fprintf('[INFO] Selected reference directory: %s\n', referenceDir);

%% Optional: ROI Specification
useROI = false;
roi = [];

prompt = '\nWould you like to specify a Region of Interest (ROI)? [y/n]: ';
roiChoice = input(prompt, 's');

if strcmpi(roiChoice, 'y') || strcmpi(roiChoice, 'yes')
    fprintf('Enter ROI coordinates:\n');
    try
        roiX = input('  X (top-left corner): ');
        roiY = input('  Y (top-left corner): ');
        roiWidth = input('  Width: ');
        roiHeight = input('  Height: ');
        
        if ~isempty(roiX) && ~isempty(roiY) && ~isempty(roiWidth) && ~isempty(roiHeight)
            roi = [roiX, roiY, roiWidth, roiHeight];
            useROI = true;
            fprintf('[INFO] ROI specified: [%d, %d, %d, %d]\n', roi);
        else
            fprintf('[WARNING] Invalid ROI input. Processing full image.\n');
        end
    catch
        fprintf('[WARNING] Error reading ROI. Processing full image.\n');
    end
end

%% Initialize Results Structure
results = struct();
results.inputImagePath = inputImagePath;
results.referenceDir = referenceDir;
results.roi = roi;
results.useROI = useROI;
results.textDetections = [];
results.objectDetections = [];
results.excludedRegions = [];
results.accuracy = struct();
results.processingTime = struct();

%% Stage 1: Load and Validate Input Image
fprintf('\n=== Stage 1: Loading Input Image ===\n');
tic;

try
    [inputImage, imageInfo] = image_loader(inputImagePath, config);
    results.imageInfo = imageInfo;
    fprintf('[INFO] Image loaded: %dx%d pixels, %d channels\n', ...
        imageInfo.height, imageInfo.width, imageInfo.channels);
catch ME
    fprintf('[ERROR] Failed to load input image: %s\n', ME.message);
    return;
end

results.processingTime.imageLoading = toc;

%% Stage 2: Load Reference Data
fprintf('\n=== Stage 2: Loading Reference Data ===\n');
tic;

try
    [referenceImages, referenceText, refInfo] = load_reference_data(referenceDir, config);
    results.referenceInfo = refInfo;
    fprintf('[INFO] Loaded %d reference images\n', refInfo.numImages);
    fprintf('[INFO] Loaded %d reference text entries\n', refInfo.numTextEntries);
catch ME
    fprintf('[ERROR] Failed to load reference data: %s\n', ME.message);
    return;
end

results.processingTime.referenceLoading = toc;

%% Stage 3: Preprocessing
fprintf('\n=== Stage 3: Preprocessing ===\n');
tic;

try
    [processedImage, preprocessInfo] = preprocessor(inputImage, config, roi, useROI);
    results.preprocessInfo = preprocessInfo;
    fprintf('[INFO] Preprocessing complete. Enhancement: %s\n', preprocessInfo.enhancementApplied);
catch ME
    fprintf('[ERROR] Preprocessing failed: %s\n', ME.message);
    return;
end

results.processingTime.preprocessing = toc;

%% Stage 4: Text Detection (OCR)
fprintf('\n=== Stage 4: Text Detection (OCR - Tesseract) ===\n');
tic;

try
    [textDetections, textRegions] = text_detector(processedImage, inputImage, ...
        referenceText, config, roi, useROI);
    results.textDetections = textDetections;
    results.textRegions = textRegions;
    
    numTextFound = sum([textDetections.confidence] >= config.ocr.confidenceThreshold);
    fprintf('[INFO] Text detection complete. Found %d text regions above threshold.\n', numTextFound);
catch ME
    fprintf('[ERROR] Text detection failed: %s\n', ME.message);
    fprintf('[WARNING] Continuing with object detection...\n');
    results.textDetections = struct('text', {}, 'confidence', {}, 'boundingBox', {});
    results.textRegions = [];
end

results.processingTime.textDetection = toc;

%% Update Excluded Regions (Text regions to exclude from object detection)
excludedRegions = [];
if ~isempty(results.textDetections)
    for i = 1:length(results.textDetections)
        if results.textDetections(i).confidence >= config.ocr.confidenceThreshold
            excludedRegions = [excludedRegions; results.textDetections(i).boundingBox];
        end
    end
end
results.excludedRegions = excludedRegions;

%% Stage 5: Object Detection (ORB)
fprintf('\n=== Stage 5: Object Detection (ORB Features) ===\n');
tic;

try
    [objectDetections, objectRegions] = object_detector(processedImage, inputImage, ...
        referenceImages, config, excludedRegions, roi, useROI);
    results.objectDetections = objectDetections;
    results.objectRegions = objectRegions;
    
    totalObjects = sum(arrayfun(@(x) length(x.instances), objectDetections));
    fprintf('[INFO] Object detection complete. Found %d object instances.\n', totalObjects);
catch ME
    fprintf('[ERROR] Object detection failed: %s\n', ME.message);
    fprintf('[WARNING] Continuing with results...\n');
    results.objectDetections = struct('referenceName', {}, 'instances', {});
    results.objectRegions = [];
end

results.processingTime.objectDetection = toc;

%% Stage 6: Calculate Accuracy Metrics
fprintf('\n=== Stage 6: Calculating Accuracy Metrics ===\n');
tic;

try
    accuracy = accuracy_calculator(results, referenceText, config);
    results.accuracy = accuracy;
    fprintf('[INFO] Accuracy calculation complete.\n');
catch ME
    fprintf('[ERROR] Accuracy calculation failed: %s\n', ME.message);
    results.accuracy = struct('textAccuracy', 0, 'objectAccuracy', 0, 'overallAccuracy', 0);
end

results.processingTime.accuracyCalculation = toc;

%% Stage 7: Visualization
fprintf('\n=== Stage 7: Generating Visualization ===\n');
tic;

try
    visualizer(inputImage, results, config);
    fprintf('[INFO] Visualization complete.\n');
catch ME
    fprintf('[ERROR] Visualization failed: %s\n', ME.message);
end

results.processingTime.visualization = toc;

%% Print Detailed Results
fprintf('\n==========================================================\n');
fprintf('                    DETAILED RESULTS\n');
fprintf('==========================================================\n');

% Text Detection Results
fprintf('\n--- Text Detection Results ---\n');
if ~isempty(results.textDetections) && length(results.textDetections) > 0
    validTextCount = 0;
    for i = 1:length(results.textDetections)
        td = results.textDetections(i);
        if td.confidence >= config.ocr.confidenceThreshold
            validTextCount = validTextCount + 1;
            fprintf('  [%d] Text: "%s"\n', validTextCount, td.text);
            fprintf('       Confidence: %.2f%%\n', td.confidence);
            fprintf('       Bounding Box: [%.0f, %.0f, %.0f, %.0f]\n', td.boundingBox);
            if isfield(td, 'matchedReference') && ~isempty(td.matchedReference)
                fprintf('       Matched Reference: "%s" (Similarity: %.2f%%)\n', ...
                    td.matchedReference, td.similarity * 100);
            end
        end
    end
    if validTextCount == 0
        fprintf('  No text detected above confidence threshold (%.0f%%).\n', ...
            config.ocr.confidenceThreshold);
    end
else
    fprintf('  No text detected.\n');
end

% Object Detection Results
fprintf('\n--- Object Detection Results ---\n');
if ~isempty(results.objectDetections) && length(results.objectDetections) > 0
    totalInstances = 0;
    for i = 1:length(results.objectDetections)
        od = results.objectDetections(i);
        if ~isempty(od.instances)
            fprintf('  Reference: "%s"\n', od.referenceName);
            for j = 1:length(od.instances)
                totalInstances = totalInstances + 1;
                inst = od.instances(j);
                fprintf('    Instance %d:\n', j);
                fprintf('       Bounding Box: [%.0f, %.0f, %.0f, %.0f]\n', inst.boundingBox);
                fprintf('       Match Confidence: %.2f%%\n', inst.confidence * 100);
                fprintf('       Matched Features: %d\n', inst.matchedFeatures);
                fprintf('       Inlier Ratio: %.2f%%\n', inst.inlierRatio * 100);
                fprintf('       Dominant Color (RGB): [%d, %d, %d]\n', inst.dominantColor);
            end
        end
    end
    if totalInstances == 0
        fprintf('  No objects detected.\n');
    end
else
    fprintf('  No objects detected.\n');
end

% Accuracy Summary
fprintf('\n--- Accuracy Summary ---\n');
fprintf('  Text Detection Accuracy:   %.2f%%\n', results.accuracy.textAccuracy * 100);
fprintf('  Object Detection Accuracy: %.2f%%\n', results.accuracy.objectAccuracy * 100);
fprintf('  Overall Pipeline Accuracy: %.2f%%\n', results.accuracy.overallAccuracy * 100);

% Processing Time Summary
fprintf('\n--- Processing Time Summary ---\n');
fprintf('  Image Loading:       %.3f seconds\n', results.processingTime.imageLoading);
fprintf('  Reference Loading:   %.3f seconds\n', results.processingTime.referenceLoading);
fprintf('  Preprocessing:       %.3f seconds\n', results.processingTime.preprocessing);
fprintf('  Text Detection:      %.3f seconds\n', results.processingTime.textDetection);
fprintf('  Object Detection:    %.3f seconds\n', results.processingTime.objectDetection);
fprintf('  Accuracy Calculation:%.3f seconds\n', results.processingTime.accuracyCalculation);
fprintf('  Visualization:       %.3f seconds\n', results.processingTime.visualization);

totalTime = results.processingTime.imageLoading + results.processingTime.referenceLoading + ...
    results.processingTime.preprocessing + results.processingTime.textDetection + ...
    results.processingTime.objectDetection + results.processingTime.accuracyCalculation + ...
    results.processingTime.visualization;
fprintf('  ---------------------------------\n');
fprintf('  Total Processing:    %.3f seconds\n', totalTime);

fprintf('\n==========================================================\n');
fprintf('                 Pipeline Complete\n');
fprintf('==========================================================\n');

%% Save Results to Workspace
assignin('base', 'pipelineResults', results);
fprintf('\n[INFO] Results saved to workspace variable: pipelineResults\n');
