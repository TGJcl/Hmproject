export interface DeepSeekMessage {
  role: string;
  content: string;
}

export interface DeepSeekRequest {
  model: string;
  messages: Array<DeepSeekMessage>;
  temperature: number;
  stream: boolean;
}

export interface DeepSeekChoice {
  message: DeepSeekMessage;
}

export interface DeepSeekResponse {
  choices: Array<DeepSeekChoice>;
}