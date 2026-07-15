import { mount, flushPromises } from '@vue/test-utils';
import WhatsAppTemplateParser from '../WhatsAppTemplateParser.vue';
import { getCadenceStepDefinitions } from 'dashboard/helper/cadenceStepDefaultsCache';

vi.mock('dashboard/helper/cadenceStepDefaultsCache', () => ({
  getCadenceStepDefinitions: vi.fn(),
}));

const mediaTemplate = {
  name: 'cadencia_primer_contacto',
  language: 'es_MX',
  category: 'MARKETING',
  components: [
    { type: 'HEADER', format: 'VIDEO' },
    { type: 'BODY', text: 'Hola' },
  ],
};

describe('WhatsAppTemplateParser.vue - cadence media prefill', () => {
  beforeEach(() => {
    getCadenceStepDefinitions.mockReset();
  });

  it('prefills media_url when a matching cadence step is configured for the inbox', async () => {
    getCadenceStepDefinitions.mockResolvedValue([
      {
        template_name: 'cadencia_primer_contacto',
        template_language: 'es_MX',
        media_url: 'https://cdn.example.com/v.mp4',
        media_type: 'video',
        media_name: null,
      },
    ]);

    const wrapper = mount(WhatsAppTemplateParser, {
      props: { template: mediaTemplate, inboxId: 7 },
    });
    await flushPromises();

    expect(getCadenceStepDefinitions).toHaveBeenCalledWith(7);
    expect(wrapper.find('input[type="url"]').element.value).toBe(
      'https://cdn.example.com/v.mp4'
    );
  });

  it('leaves the field blank when there is no matching cadence step', async () => {
    getCadenceStepDefinitions.mockResolvedValue([]);

    const wrapper = mount(WhatsAppTemplateParser, {
      props: { template: mediaTemplate, inboxId: 7 },
    });
    await flushPromises();

    expect(wrapper.find('input[type="url"]').element.value).toBe('');
  });

  it('does not look up cadence steps when no inboxId is provided', async () => {
    const wrapper = mount(WhatsAppTemplateParser, {
      props: { template: mediaTemplate },
    });
    await flushPromises();

    expect(getCadenceStepDefinitions).not.toHaveBeenCalled();
    expect(wrapper.find('input[type="url"]').element.value).toBe('');
  });
});
