import { mount, flushPromises } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import CadenceFilters from '../CadenceFilters.vue';
import { useMapGetter } from 'dashboard/composables/store';
import CadencesAPI from 'dashboard/api/cadences';

withFullI18n();

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: vi.fn(),
}));

vi.mock('dashboard/api/cadences', () => ({
  default: {
    getCadenceDefinitions: vi.fn(),
  },
}));

const inboxes = [
  { id: 1, name: 'WhatsApp A' },
  { id: 2, name: 'WhatsApp B' },
];

describe('CadenceFilters.vue', () => {
  beforeEach(() => {
    useMapGetter.mockImplementation(key => {
      if (key === 'inboxes/getInboxes') return { value: inboxes };
      return { value: [] };
    });
    CadencesAPI.getCadenceDefinitions.mockResolvedValue({
      data: [{ id: 100, name: 'Default', segment_value: null }],
    });
  });

  it('does not fetch cadence definitions when no inbox is selected', async () => {
    mount(CadenceFilters, { props: { modelValue: { inbox_id: '' } } });
    await flushPromises();

    expect(CadencesAPI.getCadenceDefinitions).not.toHaveBeenCalled();
  });

  it('fetches and lists the cadence definitions once an inbox is selected', async () => {
    const wrapper = mount(CadenceFilters, {
      props: { modelValue: { inbox_id: 1 } },
    });
    await flushPromises();

    expect(CadencesAPI.getCadenceDefinitions).toHaveBeenCalledWith(1);
    expect(wrapper.text()).toContain('Default');
  });

  it('resets the selected cadence_definition_id when the inbox changes', async () => {
    const wrapper = mount(CadenceFilters, {
      props: { modelValue: { inbox_id: 1, cadence_definition_id: 100 } },
    });
    await flushPromises();

    await wrapper.setProps({
      modelValue: { inbox_id: 2, cadence_definition_id: 100 },
    });
    await flushPromises();

    expect(wrapper.props('modelValue').cadence_definition_id).toBe('');
  });
});
