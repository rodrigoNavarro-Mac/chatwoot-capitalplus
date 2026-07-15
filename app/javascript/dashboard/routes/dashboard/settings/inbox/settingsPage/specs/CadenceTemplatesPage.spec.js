import { mount, flushPromises } from '@vue/test-utils';
import CadenceTemplatesPage from '../CadenceTemplatesPage.vue';
import CadenceStepCard from '../CadenceStepCard.vue';
import CadencesAPI from 'dashboard/api/cadences';

vi.mock('dashboard/api/cadences', () => ({
  default: {
    getStepDefinitions: vi.fn(),
    createStepDefinition: vi.fn(),
    updateStepDefinition: vi.fn(),
    deleteStepDefinition: vi.fn(),
    reorderStepDefinitions: vi.fn(),
  },
}));

const cadenceDefinition = { id: 42, name: 'Cadencia default' };

const buildStep = overrides => ({
  id: 1,
  position: 1,
  label: 'First contact',
  template_key: 'wa_primer_contacto',
  template_name: 'cadencia_primer_contacto',
  template_language: 'es_MX',
  template_namespace: null,
  schedule_type: 'immediate',
  offset_minutes: null,
  day_offset: null,
  time_of_day: null,
  wait_window_minutes: 15,
  creates_call_task: true,
  active: true,
  media_url: null,
  media_type: null,
  media_name: null,
  ...overrides,
});

const steps = [
  buildStep({}),
  buildStep({
    id: 2,
    position: 2,
    label: 'Second attempt',
    template_key: 'wa_segundo_intento',
    template_name: 'cadencia_segundo_intento',
    schedule_type: 'offset_from_last_step',
    offset_minutes: 300,
    wait_window_minutes: 120,
  }),
];

describe('CadenceTemplatesPage.vue', () => {
  beforeEach(() => {
    CadencesAPI.getStepDefinitions.mockResolvedValue({ data: steps });
  });

  it('fetches and renders the configured steps for the given cadence definition', async () => {
    const wrapper = mount(CadenceTemplatesPage, {
      props: { cadenceDefinition },
    });
    await flushPromises();

    expect(CadencesAPI.getStepDefinitions).toHaveBeenCalledWith(42);
    const cards = wrapper.findAllComponents(CadenceStepCard);
    expect(cards).toHaveLength(2);
    // template_name se renderiza como value de un <input>, no como texto plano.
    const templateNameValues = wrapper
      .findAll('input')
      .map(input => input.element.value);
    expect(templateNameValues).toContain('cadencia_primer_contacto');
    expect(templateNameValues).toContain('cadencia_segundo_intento');
  });

  it('creates a new step when "Add step" is clicked', async () => {
    CadencesAPI.createStepDefinition.mockResolvedValue({
      data: [
        ...steps,
        buildStep({
          id: 3,
          position: 3,
          template_key: 'wa_step_3',
          template_name: '',
        }),
      ],
    });
    const wrapper = mount(CadenceTemplatesPage, {
      props: { cadenceDefinition },
    });
    await flushPromises();

    await wrapper.find('button[label="Add step"]').trigger('click');
    await flushPromises();

    expect(CadencesAPI.createStepDefinition).toHaveBeenCalledWith(
      42,
      expect.objectContaining({ schedule_type: 'immediate' })
    );
    expect(wrapper.findAllComponents(CadenceStepCard)).toHaveLength(3);
  });

  it('saves a step edited inside its card', async () => {
    CadencesAPI.updateStepDefinition.mockResolvedValue({ data: steps });
    const wrapper = mount(CadenceTemplatesPage, {
      props: { cadenceDefinition },
    });
    await flushPromises();

    const firstCard = wrapper.findAllComponents(CadenceStepCard).at(0);
    await firstCard.find('input[type="number"]').setValue(45);
    await firstCard.find('button[label="Save changes"]').trigger('click');
    await flushPromises();

    expect(CadencesAPI.updateStepDefinition).toHaveBeenCalledWith(
      42,
      1,
      expect.objectContaining({ wait_window_minutes: 45 })
    );
  });

  it('deletes a step after the confirmation modal is accepted', async () => {
    CadencesAPI.deleteStepDefinition.mockResolvedValue({});
    const wrapper = mount(CadenceTemplatesPage, {
      props: { cadenceDefinition },
      global: {
        stubs: {
          'woot-delete-modal': {
            props: ['onConfirm'],
            template:
              '<button class="confirm-delete-stub" @click="onConfirm" />',
          },
        },
      },
    });
    await flushPromises();

    const firstCard = wrapper.findAllComponents(CadenceStepCard).at(0);
    await firstCard.find('button[label="Delete"]').trigger('click');
    await wrapper.find('.confirm-delete-stub').trigger('click');
    await flushPromises();

    expect(CadencesAPI.deleteStepDefinition).toHaveBeenCalledWith(42, 1);
  });

  it('emits back when the back button is clicked', async () => {
    const wrapper = mount(CadenceTemplatesPage, {
      props: { cadenceDefinition },
    });
    await flushPromises();

    const backButton = wrapper
      .findAll('button')
      .find(button => button.text().includes('Back to cadences'));
    await backButton.trigger('click');

    expect(wrapper.emitted('back')).toHaveLength(1);
  });
});
