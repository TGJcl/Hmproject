export const init: (modelPath: string, tokenizerPath: string) => void;
export const embed: (text: string) => Promise<Array<number>>;
