# AI/ML Services Design Rubric

**Applies to:** Vertex AI, Cloud Vision API, Cloud ML Engine

**Note:** v1.0 focuses on infrastructure migration. AI model serving/retraining is deferred to v1.1+.

## Signals (Decision Criteria)

### Vertex AI (Endpoints / Models)

- **Custom model inference** → SageMaker Endpoints
- **Pre-built model APIs** → AWS APIs (Rekognition, Textract, Translate, etc.)
- **Batch prediction** → SageMaker Batch Transform

### Cloud Vision API

- **Image classification, OCR** → AWS Rekognition (images) or Textract (OCR)
- **Document understanding** → AWS Textract (more powerful for docs)

### Cloud ML Engine

- **Model training** → SageMaker (managed training jobs)
- **AutoML** → SageMaker Autopilot

## 6-Criteria Rubric

Apply in order:

1. **Eliminators**: Does GCP config require AWS-unsupported features? If yes: use alternative
2. **Operational Model**: Managed (SageMaker) vs Custom (EC2 + training)?
   - Prefer managed
3. **User Preference**: From `clarified.json`, q2 (primary concern)?
   - If `"cost"` → check SageMaker Spot + Autopilot
4. **Feature Parity**: Does GCP config need model type unavailable in AWS?
   - Example: TensorFlow 2.x → SageMaker (supported)
5. **Cluster Context**: Are other compute resources running ML? Prefer SageMaker affinity
6. **Simplicity**: SageMaker endpoints (managed) > custom EC2 instances

## Examples

### Example 1: Vertex AI Endpoint (PyTorch model)

- GCP: `google_ai_platform_model` (model_name="image-classifier", framework=PYTORCH)
- Signals: Custom model inference, PyTorch
- Criterion 1 (Eliminators): PASS (PyTorch supported)
- Criterion 2 (Operational Model): SageMaker Endpoint (managed)
- → **AWS: SageMaker Endpoint (PyTorch container)**
- Confidence: `inferred`

### Example 2: Cloud Vision API

- GCP: `google_vision_api_call` (feature=TEXT_DETECTION, image_source=GCS)
- Signals: Pre-built API
- → **AWS: Textract (if document OCR) or Rekognition (if image classification)**
- Confidence: `inferred`

### Example 3: AutoML (image classification)

- GCP: `google_automl_image_classification_dataset`
- Signals: Training pipeline, classification
- Criterion 1 (Eliminators): PASS
- Criterion 2 (Operational Model): SageMaker Autopilot (managed)
- → **AWS: SageMaker Autopilot + Canvas (for low-code)**
- Confidence: `inferred`

## Output Schema

```json
{
  "gcp_type": "google_ai_platform_model",
  "gcp_address": "image-classifier-v2",
  "gcp_config": {
    "framework": "PYTORCH",
    "version": "1.9"
  },
  "aws_service": "SageMaker",
  "aws_config": {
    "endpoint_name": "image-classifier-v2",
    "instance_type": "ml.m5.large",
    "container_image": "pytorch:1.9"
  },
  "confidence": "inferred",
  "rationale": "Vertex AI custom model → SageMaker Endpoint (PyTorch supported)"
}
```

## Deferred to v1.1+

- Model retraining pipeline setup (training job automation)
- Hyperparameter tuning (SageMaker Hyperparameter Tuning Job)
- Multi-instance distributed training
- Model registry and versioning (SageMaker Model Registry)
