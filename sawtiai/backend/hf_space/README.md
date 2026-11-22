---
title: Sawti AI Backend
emoji: 🎙️
colorFrom: purple
colorTo: blue
sdk: docker
app_port: 7860
pinned: false
license: mit
short_description: Private voice-cloning API for the Sawti AI Android app
---

# Sawti AI — backend

Private API for the **Sawti AI (صوتي AI)** Android app. Every `/api` route
requires the owner's API key (a Space secret). Voice samples and generated
audio are stored only temporarily and are never published.

Generation runs on CPU (no GPU), so each sentence takes about a minute or two.

Engine: [SILMA TTS v1](https://huggingface.co/silma-ai/silma-tts)
(code MIT, weights Apache-2.0).
