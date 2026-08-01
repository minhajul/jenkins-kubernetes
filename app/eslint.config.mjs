// ESLint v10 flat config for the NestJS app.
// Run with: npm run lint
import js from '@eslint/js';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  {
    ignores: ['dist/**', 'node_modules/**'],
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ['src/**/*.ts'],
    rules: {
      // NestJS relies heavily on decorators + reflection metadata.
      '@typescript-eslint/no-explicit-any': 'warn',
      '@typescript-eslint/no-unused-vars': [
        'error',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_' },
      ],
      // Allow empty interfaces for now (NestJS DI tokens etc.)
      '@typescript-eslint/no-empty-object-type': 'off',
    },
  },
);