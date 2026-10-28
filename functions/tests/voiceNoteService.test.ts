import { getVoiceNoteUrlHandler } from '../src/services/voiceNoteService';
import { HttpsError } from 'firebase-functions/v2/https';

describe('Phase 13A - getVoiceNoteUrl Security & Access Tests', () => {
  let mockDb: any;
  let mockStorage: any;
  let mockFile: any;

  beforeEach(() => {
    mockFile = {
      exists: jest.fn().mockResolvedValue([true]),
      getSignedUrl: jest.fn().mockResolvedValue(['https://storage.googleapis.com/test-signed-url']),
    };

    mockStorage = {
      bucket: jest.fn().mockReturnValue({
        file: jest.fn().mockReturnValue(mockFile),
      }),
    };

    mockDb = {
      collection: jest.fn().mockImplementation((colName: string) => {
        if (colName === 'requests') {
          return {
            doc: jest.fn().mockImplementation((id: string) => ({
              get: jest.fn().mockResolvedValue({
                exists: id === 'req_valid',
                data: () => ({
                  id: 'req_valid',
                  crewUid: 'crew_owner_123',
                  currentHospitalId: 'hosp_mumbai_central',
                  status: id === 'req_valid' ? 'offered' : 'completed',
                  voiceNote: {
                    storagePath: 'voiceNotes/req_valid/note.m4a',
                    durationSec: 18,
                    sizeBytes: 142000,
                  },
                }),
              }),
            })),
          };
        }
        return {
          doc: jest.fn().mockReturnValue({
            get: jest.fn().mockResolvedValue({ exists: false }),
          }),
        };
      }),
    };
  });

  test('1. Owning crew member requesting signed URL succeeds', async () => {
    const callerUid = 'crew_owner_123';
    const authContext = { token: { role: 'crew' } };

    const result = await getVoiceNoteUrlHandler(
      mockDb,
      mockStorage,
      callerUid,
      authContext,
      { requestId: 'req_valid' }
    );

    expect(result.url).toBe('https://storage.googleapis.com/test-signed-url');
    expect(result.durationSec).toBe(18);
    expect(result.sizeBytes).toBe(142000);
  });

  test('2. Nurse of destination hospital on active request succeeds', async () => {
    const callerUid = 'nurse_user_abc';
    const authContext = { token: { role: 'nurse', hospitalId: 'hosp_mumbai_central' } };

    const result = await getVoiceNoteUrlHandler(
      mockDb,
      mockStorage,
      callerUid,
      authContext,
      { requestId: 'req_valid' }
    );

    expect(result.url).toBe('https://storage.googleapis.com/test-signed-url');
  });

  test('3. Nurse of another hospital requesting URL fails with permission-denied', async () => {
    const callerUid = 'nurse_user_different';
    const authContext = { token: { role: 'nurse', hospitalId: 'hosp_other_hospital' } };

    await expect(
      getVoiceNoteUrlHandler(
        mockDb,
        mockStorage,
        callerUid,
        authContext,
        { requestId: 'req_valid' }
      )
    ).rejects.toThrow(HttpsError);
  });

  test('4. Nurse requesting URL for terminal request fails with permission-denied', async () => {
    mockDb.collection = jest.fn().mockReturnValue({
      doc: jest.fn().mockReturnValue({
        get: jest.fn().mockResolvedValue({
          exists: true,
          data: () => ({
            id: 'req_terminal',
            crewUid: 'crew_owner_123',
            currentHospitalId: 'hosp_mumbai_central',
            status: 'completed',
            voiceNote: {
              storagePath: 'voiceNotes/req_terminal/note.m4a',
              durationSec: 14,
              sizeBytes: 90000,
            },
          }),
        }),
      }),
    });

    const callerUid = 'nurse_user_abc';
    const authContext = { token: { role: 'nurse', hospitalId: 'hosp_mumbai_central' } };

    await expect(
      getVoiceNoteUrlHandler(
        mockDb,
        mockStorage,
        callerUid,
        authContext,
        { requestId: 'req_terminal' }
      )
    ).rejects.toThrow('Cannot access voice note for a completed or cancelled request.');
  });

  test('5. Unauthorized user requesting URL fails with permission-denied', async () => {
    const callerUid = 'random_stranger_999';
    const authContext = { token: {} };

    await expect(
      getVoiceNoteUrlHandler(
        mockDb,
        mockStorage,
        callerUid,
        authContext,
        { requestId: 'req_valid' }
      )
    ).rejects.toThrow('Unauthorized: Caller is neither the owning crew nor an active nurse at the destination hospital.');
  });
});
