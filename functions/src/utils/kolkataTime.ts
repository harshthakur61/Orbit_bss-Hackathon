/**
 * Asia/Kolkata Timezone Utilities
 * Standard UTC offset: +05:30 (No Daylight Savings Time)
 */

export const KOLKATA_OFFSET_MS = (5 * 60 + 30) * 60 * 1000;

export interface KolkataDateTimeComponents {
  year: number;
  month: number; // 1 - 12
  day: number; // 1 - 31
  hours: number; // 0 - 23
  minutes: number; // 0 - 59
  isoDayOfWeek: number; // 1 = Monday, ..., 7 = Sunday
  dateKey: string; // YYYYMMDD
  timeKey: string; // HHmm
  timeFormatted: string; // HH:mm
}

/**
 * Extracts Asia/Kolkata date and time components from any UTC Date
 */
export function getKolkataComponents(date: Date = new Date()): KolkataDateTimeComponents {
  const shiftedMs = date.getTime() + KOLKATA_OFFSET_MS;
  const shifted = new Date(shiftedMs);

  const year = shifted.getUTCFullYear();
  const month = shifted.getUTCMonth() + 1;
  const day = shifted.getUTCDate();
  const hours = shifted.getUTCHours();
  const minutes = shifted.getUTCMinutes();
  const utcDay = shifted.getUTCDay(); // 0 = Sun, 1 = Mon ... 6 = Sat
  const isoDayOfWeek = utcDay === 0 ? 7 : utcDay;

  const pad2 = (n: number) => n.toString().padStart(2, '0');
  const dateKey = `${year}${pad2(month)}${pad2(day)}`;
  const timeKey = `${pad2(hours)}${pad2(minutes)}`;
  const timeFormatted = `${pad2(hours)}:${pad2(minutes)}`;

  return {
    year,
    month,
    day,
    hours,
    minutes,
    isoDayOfWeek,
    dateKey,
    timeKey,
    timeFormatted,
  };
}

/**
 * Parses an Asia/Kolkata dateKey (YYYYMMDD) and time string (HH:mm) into a UTC Date
 */
export function parseKolkataDateTime(dateKey: string, timeStr: string): Date {
  if (!/^\d{8}$/.test(dateKey)) {
    throw new Error(`Invalid dateKey format: ${dateKey}. Expected YYYYMMDD.`);
  }

  const cleanTime = timeStr.trim();
  const timeMatch = /^(\d{1,2}):(\d{2})$/.exec(cleanTime);
  if (!timeMatch) {
    throw new Error(`Invalid time format: ${timeStr}. Expected HH:mm.`);
  }

  const year = parseInt(dateKey.substring(0, 4), 10);
  const month = parseInt(dateKey.substring(4, 6), 10);
  const day = parseInt(dateKey.substring(6, 8), 10);
  const hours = parseInt(timeMatch[1], 10);
  const minutes = parseInt(timeMatch[2], 10);

  // UTC epoch representation of that instant in Asia/Kolkata
  const utcEquivalentMs = Date.UTC(year, month - 1, day, hours, minutes, 0, 0);
  const epochMs = utcEquivalentMs - KOLKATA_OFFSET_MS;

  return new Date(epochMs);
}

/**
 * Converts "HH:mm" to total minutes from midnight
 */
export function timeStringToMinutes(timeStr: string): number {
  const parts = timeStr.trim().split(':');
  if (parts.length !== 2) return 0;
  return parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10);
}

/**
 * Converts total minutes from midnight to "HH:mm"
 */
export function minutesToTimeString(minutes: number): string {
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  return `${h.toString().padStart(2, '0')}:${m.toString().padStart(2, '0')}`;
}

/**
 * Generates regular slot intervals between openTime and closeTime
 */
export function generateDaySlotIntervals(
  openTime: string,
  closeTime: string,
  slotDurationMin: number
): string[] {
  const startMin = timeStringToMinutes(openTime);
  const endMin = timeStringToMinutes(closeTime);
  const duration = Math.max(10, slotDurationMin);

  const slots: string[] = [];
  for (let m = startMin; m + duration <= endMin; m += duration) {
    slots.push(minutesToTimeString(m));
  }
  return slots;
}
