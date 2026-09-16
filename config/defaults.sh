#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Shared defaults. Environment variables already set by the user take precedence.
# This file is sourced; it must not enable `set -u` on its own.

# Gemini
: "${GEMINI_MODEL:=gemini-2.5-flash}"

# Ollama
: "${OLLAMA_HOST:=http://localhost:11434}"
: "${OLLAMA_MODEL:=llama3.1}"

# OpenAI
: "${OPENAI_MODEL:=gpt-4o-mini}"

# Temporary files
: "${TMPDIR:=/tmp}"
