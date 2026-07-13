import { mount, flushPromises } from '@vue/test-utils';
import CadenceTemplatesPage from '../CadenceTemplatesPage.vue';
import CadencesAPI from 'dashboard/api/cadences';

vi.mock('dashboard/api/cadences', () => ({
  default: {
    getTemplateMappings: vi.fn(),
    updateTemplateMappings: vi.fn(),
    resetTemplateMapping: vi.fn(),
  },
}));

const inbox = { id: 42 };

const entries = [
  {
    step: 1,
    template_key: 'wa_primer_contacto',
    name: 'cadencia_primer_contacto',
    language: 'es_MX',
    namespace: null,
    is_custom: false,
  },
  {
    step: 2,
    template_key: 'wa_segundo_intento',
    name: 'cadencia_segundo_intento_custom',
    language: 'es_MX',
    namespace: null,
    is_custom: true,
  },
];

describe('CadenceTemplatesPage.vue', () => {
  beforeEach(() => {
    CadencesAPI.getTemplateMappings.mockResolvedValue({ data: entries });
  });

  it('fetches and renders the fixed cadence steps for the given inbox', async () => {
    const wrapper = mount(CadenceTemplatesPage, { props: { inbox } });
    await flushPromises();

    expect(CadencesAPI.getTemplateMappings).toHaveBeenCalledWith(42);
    const nameInputs = wrapper.findAll('input');
    expect(nameInputs.length).toBeGreaterThan(0);
    expect(wrapper.text()).toContain('cadencia_primer_contacto');
    expect(wrapper.text()).toContain('cadencia_segundo_intento_custom');
  });

  it('only shows a reset button for the overridden entry', async () => {
    const wrapper = mount(CadenceTemplatesPage, { props: { inbox } });
    await flushPromises();

    expect(wrapper.findAll('button[type="button"]')).toHaveLength(1);
  });

  it('sends the edited entries when saving', async () => {
    CadencesAPI.updateTemplateMappings.mockResolvedValue({ data: entries });
    const wrapper = mount(CadenceTemplatesPage, { props: { inbox } });
    await flushPromises();

    await wrapper.find('button[type="submit"]').trigger('click');
    await flushPromises();

    expect(CadencesAPI.updateTemplateMappings).toHaveBeenCalledWith(
      42,
      entries.map(({ template_key, name, language, namespace }) => ({
        template_key,
        name,
        language,
        namespace,
      }))
    );
  });

  it('resets the overridden entry to its default mapping', async () => {
    CadencesAPI.resetTemplateMapping.mockResolvedValue({
      data: entries.map(entry =>
        entry.template_key === 'wa_segundo_intento'
          ? { ...entry, name: 'cadencia_segundo_intento', is_custom: false }
          : entry
      ),
    });
    const wrapper = mount(CadenceTemplatesPage, { props: { inbox } });
    await flushPromises();

    await wrapper.find('button[type="button"]').trigger('click');
    await flushPromises();

    expect(CadencesAPI.resetTemplateMapping).toHaveBeenCalledWith(
      42,
      'wa_segundo_intento'
    );
  });
});
