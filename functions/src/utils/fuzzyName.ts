export const DEFAULT_NAME_SIMILARITY_THRESHOLD = 0.75;

const TITLES_TO_REMOVE = new Set(['mr', 'mrs', 'ms', 'dr', 'shri', 'shree', 'smt', 'md']);

/**
 * Normalizes a name string:
 * - Lowercases and strips punctuation/special characters
 * - Strips common honorific titles
 * - Returns array of meaningful tokens
 */
export function tokenizeName(name: string): string[] {
  if (!name) return [];

  const clean = name
    .toLowerCase()
    .replace(/[.,\/#!$%\^&\*;:{}=\-_`~()]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();

  return clean
    .split(' ')
    .filter((token) => token.length > 0 && !TITLES_TO_REMOVE.has(token));
}

/**
 * Calculates standard Levenshtein distance between two strings
 */
export function levenshteinDistance(s1: string, s2: string): number {
  const m = s1.length;
  const n = s2.length;
  const dp: number[][] = Array.from({ length: m + 1 }, () => Array(n + 1).fill(0));

  for (let i = 0; i <= m; i++) dp[i][0] = i;
  for (let j = 0; j <= n; j++) dp[0][j] = j;

  for (let i = 1; i <= m; i++) {
    for (let j = 1; j <= n; j++) {
      if (s1[i - 1] === s2[j - 1]) {
        dp[i][j] = dp[i - 1][j - 1];
      } else {
        dp[i][j] = 1 + Math.min(dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]);
      }
    }
  }

  return dp[m][n];
}

/**
 * Computes string similarity between 0.0 and 1.0 using Levenshtein distance
 */
export function stringSimilarity(s1: string, s2: string): number {
  if (s1 === s2) return 1.0;
  if (!s1 || !s2) return 0.0;
  const maxLen = Math.max(s1.length, s2.length);
  if (maxLen === 0) return 1.0;
  const dist = levenshteinDistance(s1, s2);
  return 1.0 - dist / maxLen;
}

/**
 * Determines whether two names match using fuzzy token & similarity comparison:
 * 1. Checks exact normalized string match.
 * 2. Checks token subset & initial match (e.g., "R. Sharma" vs "Rahul Sharma").
 * 3. Checks token-level / full-string similarity against threshold.
 */
export function fuzzyMatchNames(
  nameA: string,
  nameB: string,
  threshold: number = DEFAULT_NAME_SIMILARITY_THRESHOLD
): boolean {
  if (!nameA || !nameB) return false;

  const tokensA = tokenizeName(nameA);
  const tokensB = tokenizeName(nameB);

  if (tokensA.length === 0 || tokensB.length === 0) return false;

  const strA = tokensA.join(' ');
  const strB = tokensB.join(' ');

  // 1. Direct match after tokenization
  if (strA === strB) return true;

  // 2. Direct string similarity check
  const directScore = stringSimilarity(strA, strB);
  if (directScore >= threshold) return true;

  // 3. Token-based matching (handles middle names and initials)
  // Check if every token in the shorter name matches or is an initial of a token in the longer name
  const [shorter, longer] = tokensA.length <= tokensB.length ? [tokensA, tokensB] : [tokensB, tokensA];

  let matchedTokens = 0;
  const usedLongerIndices = new Set<number>();

  for (const sToken of shorter) {
    for (let i = 0; i < longer.length; i++) {
      if (usedLongerIndices.has(i)) continue;
      const lToken = longer[i];

      // Exact token match
      if (sToken === lToken) {
        matchedTokens++;
        usedLongerIndices.add(i);
        break;
      }

      // Initial match (e.g. 'r' matches 'rahul' or 'ramesh')
      if (sToken.length === 1 && lToken.startsWith(sToken)) {
        matchedTokens++;
        usedLongerIndices.add(i);
        break;
      }
      if (lToken.length === 1 && sToken.startsWith(lToken)) {
        matchedTokens++;
        usedLongerIndices.add(i);
        break;
      }

      // High token similarity for minor typos (e.g. 'sharma' vs 'sharmma')
      if (stringSimilarity(sToken, lToken) >= 0.8) {
        matchedTokens++;
        usedLongerIndices.add(i);
        break;
      }
    }
  }

  // If all tokens of the shorter name are accounted for in the longer name
  if (matchedTokens === shorter.length) {
    return true;
  }

  // Token Jaccard-like ratio
  const ratio = (matchedTokens * 2) / (tokensA.length + tokensB.length);
  return ratio >= threshold;
}
