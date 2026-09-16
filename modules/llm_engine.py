import os
import json
import google.generativeai as genai

genai.configure(api_key=os.getenv("GEMINI_API_KEY"))

MODEL_NAME = "gemini-2.0-flash"


def _get_model():
    return genai.GenerativeModel(MODEL_NAME)


def analyze_content(content: str) -> dict:
    """
    Analyzes given content and returns structured insights as a dict.
    """
    prompt = f"""
You are a CRM assistant. Analyze the following content and return a JSON object
with keys: "summary", "sentiment", "key_points" (a list), and "suggested_action".

Content:
{content}

Return ONLY valid JSON, no markdown formatting, no code fences.
"""
    model = _get_model()
    response = model.generate_content(
        prompt,
        generation_config={"response_mime_type": "application/json"},
    )
    return json.loads(response.text)


def generate_email(context: str, tone: str = "professional") -> dict:
    """
    Generates an email draft based on context and desired tone.
    Returns a dict with "subject" and "body".
    """
    prompt = f"""
You are a CRM assistant writing a business email.
Tone: {tone}
Context:
{context}

Return ONLY valid JSON with keys "subject" and "body". No markdown formatting, no code fences.
"""
    model = _get_model()
    response = model.generate_content(
        prompt,
        generation_config={"response_mime_type": "application/json"},
    )
    return json.loads(response.text)


def analyze_document(document_text: str) -> dict:
    """
    Analyzes an uploaded/OCR'd document and extracts structured data.
    Returns a dict with extracted fields relevant to the CRM.
    """
    prompt = f"""
You are a CRM assistant extracting structured information from a document.
Document text:
{document_text}

Return ONLY valid JSON with keys: "document_type", "extracted_fields" (an object),
and "summary". No markdown formatting, no code fences.
"""
    model = _get_model()
    response = model.generate_content(
        prompt,
        generation_config={"response_mime_type": "application/json"},
    )
    return json.loads(response.text)
