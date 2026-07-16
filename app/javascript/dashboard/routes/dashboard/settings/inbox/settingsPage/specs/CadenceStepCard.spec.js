import { mount } from '@vue/test-utils';
import { useMapGetter } from 'dashboard/composables/store';
import CadenceStepCard from '../CadenceStepCard.vue';

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: vi.fn(),
}));

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
  body_variables: {},
  ...overrides,
});

const approvedTemplateWithVariablesAndMedia = {
  name: 'cadencia_primer_contacto',
  language: 'es_MX',
  namespace: 'ns_123',
  components: [
    { type: 'HEADER', format: 'VIDEO' },
    { type: 'BODY', text: 'Hola {{1}}, tu cita es el {{2}}' },
  ],
};

const mountCard = (stepOverrides = {}, templates = []) => {
  useMapGetter.mockReturnValue({ value: () => templates });
  return mount(CadenceStepCard, {
    props: { step: buildStep(stepOverrides), index: 0, inboxId: 1 },
  });
};

describe('CadenceStepCard.vue', () => {
  beforeEach(() => {
    useMapGetter.mockReset();
  });

  describe('manual mode (no matching approved template found for the inbox)', () => {
    it('does not show offset/day fields for an immediate schedule', () => {
      const wrapper = mountCard({ schedule_type: 'immediate' });

      expect(wrapper.find('input[type="time"]').exists()).toBe(false);
      // only wait_window_minutes should be a number input
      expect(wrapper.findAll('input[type="number"]')).toHaveLength(1);
    });

    it('shows the offset field for an offset_from_last_step schedule', () => {
      const wrapper = mountCard({
        schedule_type: 'offset_from_last_step',
        offset_minutes: 300,
      });

      expect(wrapper.findAll('input[type="number"]')).toHaveLength(2);
    });

    it('shows day_offset and time_of_day fields for a day_offset_at_time schedule', () => {
      const wrapper = mountCard({
        schedule_type: 'day_offset_at_time',
        day_offset: 1,
        time_of_day: '09:00',
      });

      expect(wrapper.find('input[type="time"]').exists()).toBe(true);
      expect(wrapper.findAll('input[type="number"]')).toHaveLength(2); // day_offset + wait_window_minutes
    });

    it('only shows the media_url field once a media type is selected', async () => {
      const wrapper = mountCard({ media_type: null });

      expect(wrapper.find('input[type="url"]').exists()).toBe(false);
      expect(wrapper.text()).not.toContain('File name');

      // selects in manual mode: [template picker, schedule type, media type]
      const [, , mediaTypeSelect] = wrapper.findAll('select');
      await mediaTypeSelect.setValue('document');

      expect(wrapper.find('input[type="url"]').exists()).toBe(true);
      expect(wrapper.text()).toContain('File name');
    });

    it('does not show the media_name field for a video attachment', async () => {
      const wrapper = mountCard({ media_type: null });

      const [, , mediaTypeSelect] = wrapper.findAll('select');
      await mediaTypeSelect.setValue('video');

      expect(wrapper.find('input[type="url"]').exists()).toBe(true);
      expect(wrapper.text()).not.toContain('File name');
    });

    it('emits save with the form payload, nulling out irrelevant schedule fields', async () => {
      const wrapper = mountCard({ schedule_type: 'immediate' });

      await wrapper.find('button[label="Save changes"]').trigger('click');

      const [payload] = wrapper.emitted('save')[0];
      expect(payload.offset_minutes).toBeNull();
      expect(payload.day_offset).toBeNull();
      expect(payload.time_of_day).toBeNull();
      expect(payload.wait_window_minutes).toBe(15);
    });

    it('emits delete when the delete button is clicked', async () => {
      const wrapper = mountCard();

      await wrapper.find('button[label="Delete"]').trigger('click');

      expect(wrapper.emitted('delete')).toHaveLength(1);
    });
  });

  describe('picklist mode (an approved template matches the step)', () => {
    it('auto-selects the matching template and hides the manual name/language inputs', () => {
      const wrapper = mountCard({}, [approvedTemplateWithVariablesAndMedia]);

      expect(wrapper.text()).toContain('cadencia_primer_contacto');
      // no manual media-type select is rendered once a real template is matched
      expect(wrapper.findAll('select')).toHaveLength(2);
    });

    it('detects the media header type and only asks for the link', () => {
      const wrapper = mountCard({}, [approvedTemplateWithVariablesAndMedia]);

      expect(wrapper.find('input[type="url"]').exists()).toBe(true);
      expect(wrapper.text()).toContain('video');
    });

    it('renders one input per body variable detected in the template', () => {
      const wrapper = mountCard({}, [approvedTemplateWithVariablesAndMedia]);

      expect(wrapper.text()).toContain('Variable 1');
      expect(wrapper.text()).toContain('Variable 2');
    });

    it('shows clickable Liquid hints so the admin knows what can be mapped', () => {
      const wrapper = mountCard({}, [approvedTemplateWithVariablesAndMedia]);

      expect(wrapper.text()).toContain('{{ contact.name }}');
      expect(wrapper.text()).toContain('{{ account.name }}');
    });

    it('inserts a clicked Liquid hint into its corresponding variable field', async () => {
      const wrapper = mountCard({}, [approvedTemplateWithVariablesAndMedia]);

      // hint chips render grouped per variable, in order: variable 1's hints first
      const hintChips = wrapper.findAll('button.font-mono');
      await hintChips[0].trigger('click');

      await wrapper.find('button[label="Save changes"]').trigger('click');

      const [payload] = wrapper.emitted('save')[0];
      expect(payload.body_variables['1']).toBe('{{ contact.name }}');
    });

    it('emits save with the template namespace, detected media type and body_variables', async () => {
      const wrapper = mountCard({}, [approvedTemplateWithVariablesAndMedia]);

      await wrapper
        .find('input[type="url"]')
        .setValue('https://cdn.example.com/v.mp4');
      await wrapper.find('button[label="Save changes"]').trigger('click');

      const [payload] = wrapper.emitted('save')[0];
      expect(payload.template_namespace).toBe('ns_123');
      expect(payload.media_type).toBe('video');
      expect(payload.media_url).toBe('https://cdn.example.com/v.mp4');
      expect(payload.body_variables).toEqual({ 1: '', 2: '' });
    });
  });
});
