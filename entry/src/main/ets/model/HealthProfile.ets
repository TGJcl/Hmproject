export class HealthProfile {
  age: string = '';
  height: string = '';
  weight: string = '';
  sleep: string = '';
  exercise: string = '';
  symptom: string = '';

  isComplete(): boolean {
    return this.age !== '' && this.height !== '' && this.weight !== '' &&
      this.sleep !== '' && this.exercise !== '' && this.symptom !== '';
  }

  getField(key: string): string {
    switch (key) {
      case 'age': return this.age;
      case 'height': return this.height;
      case 'weight': return this.weight;
      case 'sleep': return this.sleep;
      case 'exercise': return this.exercise;
      case 'symptom': return this.symptom;
      default: return '';
    }
  }

  setField(key: string, value: string): void {
    switch (key) {
      case 'age': this.age = value; break;
      case 'height': this.height = value; break;
      case 'weight': this.weight = value; break;
      case 'sleep': this.sleep = value; break;
      case 'exercise': this.exercise = value; break;
      case 'symptom': this.symptom = value; break;
      default: break;
    }
  }

  toMemoryText(): string {
    return '年龄' + this.age + '，身高' + this.height + '，体重' + this.weight +
      '，睡眠' + this.sleep + '，运动' + this.exercise + '，症状' + this.symptom;
  }
}
