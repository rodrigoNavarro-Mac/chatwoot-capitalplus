import { mount } from '@vue/test-utils';
import CadenceStepCard from '../CadenceStepCard.vue';

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

describe('CadenceStepCard.vue', () => {
  it('does not show offset/day fields for an immediate schedule', () => {
    const wrapper = mount(CadenceStepCard, {
      props: { step: buildStep({ schedule_type: 'immediate' }), index: 0 },
    });

    expect(wrapper.find('input[type="time"]').exists()).toBe(false);
    // only wait_window_minutes should be a number input
    expect(wrapper.findAll('input[type="number"]')).toHaveLength(1);
  });

  it('shows the offset field for an offset_from_last_step schedule', () => {
    const wrapper = mount(CadenceStepCard, {
      props: {
        step: buildStep({
          schedule_type: 'offset_from_last_step',
          offset_minutes: 300,
        }),
        index: 1,
      },
    });

    expect(wrapper.findAll('input[type="number"]')).toHaveLength(2);
  });

  it('shows day_offset and time_of_day fields for a day_offset_at_time schedule', () => {
    const wrapper = mount(CadenceStepCard, {
      props: {
        step: buildStep({
          schedule_type: 'day_offset_at_time',
          day_offset: 1,
          time_of_day: '09:00',
        }),
        index: 2,
      },
    });

    expect(wrapper.find('input[type="time"]').exists()).toBe(true);
    expect(wrapper.findAll('input[type="number"]')).toHaveLength(2); // day_offset + wait_window_minutes
  });

  it('only shows the media_url field once a media type is selected', async () => {
    const wrapper = mount(CadenceStepCard, {
      props: { step: buildStep({ media_type: null }), index: 0 },
    });

    expect(wrapper.find('input[type="url"]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('File name');

    const [, mediaTypeSelect] = wrapper.findAll('select');
    await mediaTypeSelect.setValue('document');

    expect(wrapper.find('input[type="url"]').exists()).toBe(true);
    expect(wrapper.text()).toContain('File name');
  });

  it('does not show the media_name field for a video attachment', async () => {
    const wrapper = mount(CadenceStepCard, {
      props: { step: buildStep({ media_type: null }), index: 0 },
    });

    const [, mediaTypeSelect] = wrapper.findAll('select');
    await mediaTypeSelect.setValue('video');

    expect(wrapper.find('input[type="url"]').exists()).toBe(true);
    expect(wrapper.text()).not.toContain('File name');
  });

  it('emits save with the form payload, nulling out irrelevant schedule fields', async () => {
    const wrapper = mount(CadenceStepCard, {
      props: { step: buildStep({ schedule_type: 'immediate' }), index: 0 },
    });

    await wrapper.find('button[label="Save changes"]').trigger('click');

    const [payload] = wrapper.emitted('save')[0];
    expect(payload.offset_minutes).toBeNull();
    expect(payload.day_offset).toBeNull();
    expect(payload.time_of_day).toBeNull();
    expect(payload.wait_window_minutes).toBe(15);
  });

  it('emits delete when the delete button is clicked', async () => {
    const wrapper = mount(CadenceStepCard, {
      props: { step: buildStep({}), index: 0 },
    });

    await wrapper.find('button[label="Delete"]').trigger('click');

    expect(wrapper.emitted('delete')).toHaveLength(1);
  });
});
