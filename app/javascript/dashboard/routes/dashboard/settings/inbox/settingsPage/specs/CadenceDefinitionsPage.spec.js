import { mount, flushPromises } from '@vue/test-utils';
import CadenceDefinitionsPage from '../CadenceDefinitionsPage.vue';
import CadencesAPI from 'dashboard/api/cadences';

vi.mock('dashboard/api/cadences', () => ({
  default: {
    getCadenceDefinitions: vi.fn(),
    createCadenceDefinition: vi.fn(),
    updateCadenceDefinition: vi.fn(),
    deleteCadenceDefinition: vi.fn(),
  },
}));

const inbox = { id: 7 };

const buildDefinition = overrides => ({
  id: 1,
  name: 'Default',
  segment_value: null,
  is_default: true,
  active: true,
  steps_count: 3,
  enrollments_count: 10,
  ...overrides,
});

const definitions = [
  buildDefinition({}),
  buildDefinition({
    id: 2,
    name: 'Inversión — A',
    segment_value: 'Inversión',
    is_default: false,
  }),
];

const CadenceTemplatesPageStub = {
  props: ['cadenceDefinition'],
  emits: ['back'],
  template:
    '<button class="steps-stub" @click="$emit(\'back\')">{{ cadenceDefinition.name }}</button>',
};

describe('CadenceDefinitionsPage.vue', () => {
  beforeEach(() => {
    CadencesAPI.getCadenceDefinitions.mockResolvedValue({ data: definitions });
  });

  const mountPage = () =>
    mount(CadenceDefinitionsPage, {
      props: { inbox },
      global: {
        stubs: {
          CadenceTemplatesPage: CadenceTemplatesPageStub,
          'woot-delete-modal': {
            props: ['onConfirm'],
            template:
              '<button class="confirm-delete-stub" @click="onConfirm" />',
          },
        },
      },
    });

  it('fetches and lists the cadence definitions for the inbox', async () => {
    const wrapper = mountPage();
    await flushPromises();

    expect(CadencesAPI.getCadenceDefinitions).toHaveBeenCalledWith(7);
    expect(wrapper.text()).toContain('Default');
    expect(wrapper.text()).toContain('Inversión — A');
  });

  it('creates a new cadence definition', async () => {
    CadencesAPI.createCadenceDefinition.mockResolvedValue({
      data: [
        ...definitions,
        buildDefinition({
          id: 3,
          name: 'Inversión — B',
          segment_value: 'Inversión',
          is_default: false,
        }),
      ],
    });
    const wrapper = mountPage();
    await flushPromises();

    await wrapper.find('button[label="Add cadence"]').trigger('click');
    await wrapper.find('input').setValue('Inversión — B');
    await wrapper.find('button[label="Create"]').trigger('click');
    await flushPromises();

    expect(CadencesAPI.createCadenceDefinition).toHaveBeenCalledWith(
      7,
      expect.objectContaining({ name: 'Inversión — B' })
    );
  });

  it('marks a definition as default', async () => {
    CadencesAPI.updateCadenceDefinition.mockResolvedValue({
      data: definitions,
    });
    const wrapper = mountPage();
    await flushPromises();

    await wrapper.find('button[label="Mark as default"]').trigger('click');

    expect(CadencesAPI.updateCadenceDefinition).toHaveBeenCalledWith(2, {
      is_default: true,
    });
  });

  it('navigates to the step editor and back', async () => {
    const wrapper = mountPage();
    await flushPromises();

    const manageButtons = wrapper.findAll('button[label="Manage steps"]');
    await manageButtons[0].trigger('click');

    expect(wrapper.findComponent(CadenceTemplatesPageStub).exists()).toBe(true);

    await wrapper.find('.steps-stub').trigger('click');
    await flushPromises();

    expect(wrapper.findComponent(CadenceTemplatesPageStub).exists()).toBe(
      false
    );
  });

  it('deletes a cadence definition after confirmation', async () => {
    CadencesAPI.deleteCadenceDefinition.mockResolvedValue({});
    const wrapper = mountPage();
    await flushPromises();

    const deleteButtons = wrapper.findAll('button[label="Delete"]');
    await deleteButtons[0].trigger('click');
    await wrapper.find('.confirm-delete-stub').trigger('click');
    await flushPromises();

    expect(CadencesAPI.deleteCadenceDefinition).toHaveBeenCalledWith(1);
  });
});
