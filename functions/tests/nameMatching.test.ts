import { evaluateOwnerRule } from '../src/rules/ownerRules';
import { fuzzyMatchNames } from '../src/utils/fuzzyName';

describe('Fuzzy Name Matching & Owner Rules', () => {
  describe('fuzzyMatchNames', () => {
    test('matches identical names ignoring case and whitespace', () => {
      expect(fuzzyMatchNames('Rahul Sharma', 'RAHUL SHARMA')).toBe(true);
      expect(fuzzyMatchNames('  Rahul   Sharma  ', 'rahul sharma')).toBe(true);
    });

    test('matches names with middle names / initials', () => {
      expect(fuzzyMatchNames('Rahul Sharma', 'Rahul Ramesh Sharma')).toBe(true);
      expect(fuzzyMatchNames('R. Sharma', 'Rahul Sharma')).toBe(true);
      expect(fuzzyMatchNames('Rahul R. Sharma', 'Rahul Ramesh Sharma')).toBe(true);
    });

    test('ignores honorific titles like Mr., Dr., Shri', () => {
      expect(fuzzyMatchNames('Mr. Rahul Sharma', 'Rahul Sharma')).toBe(true);
      expect(fuzzyMatchNames('Dr. Priya Nair', 'Priya Nair')).toBe(true);
      expect(fuzzyMatchNames('Shri Rajesh Kulkarni', 'Rajesh Kulkarni')).toBe(true);
    });

    test('tolerates single typo / minor spelling differences', () => {
      expect(fuzzyMatchNames('Rahul Sharma', 'Rahul Sharmma')).toBe(true);
    });

    test('rejects completely distinct names', () => {
      expect(fuzzyMatchNames('Rahul Sharma', 'Amitabh Bachchan')).toBe(false);
      expect(fuzzyMatchNames('Priya Nair', 'Sneha Deshmukh')).toBe(false);
    });
  });

  describe('evaluateOwnerRule', () => {
    test('passes without review flag when owner matches driver name', () => {
      const result = evaluateOwnerRule('Rahul Sharma', 'Rahul Sharma');
      expect(result.matches).toBe(true);
      expect(result.reviewReason).toBeNull();
    });

    test('passes when owner matches registered vendor name', () => {
      const result = evaluateOwnerRule('Apex Emergency Fleet LLP', 'Rahul Sharma', 'Apex Emergency Fleet');
      expect(result.matches).toBe(true);
      expect(result.reviewReason).toBeNull();
    });

    test('flags institutional / hospital owners for manual review instead of hard rejecting', () => {
      const result = evaluateOwnerRule('Lilavati Hospital and Research Centre', 'Rahul Sharma');
      expect(result.matches).toBe(false);
      expect(result.reviewReason).toContain('Flagged for standard institutional credential review');
    });

    test('flags unknown private owners for review instead of hard rejecting', () => {
      const result = evaluateOwnerRule('Vikramaditya Logistics Private Limited', 'Rahul Sharma');
      expect(result.matches).toBe(false);
      expect(result.reviewReason).toContain('Flagged for manual review');
    });
  });
});
