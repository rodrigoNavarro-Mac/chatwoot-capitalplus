export const FLOW_TEMPLATES = [
  {
    id: 'inmobiliaria',
    name: 'Inmobiliaria — Desarrollo residencial',
    description:
      'Lead pre-calificado llega tras confirmar interés. Captura tipo de contacto, timeline y horario. Hace handover al asesor.',
    icon: 'i-lucide-building-2',
    config: {
      variables: {
        desarrollo: 'Mi Desarrollo',
        ciudad: 'Ciudad',
        precio_desde: '$2,800,000',
        telefono: '33 1234 5678',
        horario: 'Lun–Vie 9am–7pm',
      },
      initial_step: 'bienvenida',
      steps: {
        bienvenida: {
          message:
            '¡Excelente! 🙌 Nos da mucho gusto que quieras conocer más sobre *{{desarrollo}}* en {{ciudad}}.\n\nPrecios desde {{precio_desde}}.\n\n¿Cómo prefieres dar el siguiente paso?\n\n1️⃣ Visitar el desarrollo en persona\n2️⃣ Agendar una llamada con un asesor\n3️⃣ Agendar una videollamada',
          transitions: [
            {
              when: {
                contains: ['1', 'visita', 'visitar', 'persona', 'presencial'],
              },
              next_step: 'timeline',
            },
            {
              when: {
                contains: ['2', 'llamada', 'llamen', 'telefono', 'teléfono'],
              },
              next_step: 'timeline_llamada',
            },
            {
              when: {
                contains: ['3', 'video', 'zoom', 'meet', 'videollamada'],
              },
              next_step: 'timeline',
            },
            { when: { default: true }, next_step: 'no_entendido' },
          ],
        },
        timeline: {
          message:
            'Una pregunta rápida para preparar mejor tu atención 👌\n\n¿En qué momento planeas tomar una decisión?\n\n1️⃣ Pronto — estoy listo para decidir\n2️⃣ En unos meses — estoy evaluando\n3️⃣ Aún estoy explorando opciones',
          transitions: [
            {
              when: {
                contains: ['1', 'pronto', 'listo', 'ya', 'decidido', 'ahora'],
              },
              next_step: 'solicitud_horario',
            },
            {
              when: { contains: ['2', 'meses', 'evaluando', 'pensando'] },
              next_step: 'solicitud_horario',
            },
            {
              when: { contains: ['3', 'explorando', 'investigando', 'viendo'] },
              next_step: 'solicitud_horario',
            },
            { when: { default: true }, next_step: 'solicitud_horario' },
          ],
        },
        timeline_llamada: {
          message:
            'Una pregunta rápida para preparar mejor tu atención 👌\n\n¿En qué momento planeas tomar una decisión?\n\n1️⃣ Pronto — estoy listo para decidir\n2️⃣ En unos meses — estoy evaluando\n3️⃣ Aún estoy explorando opciones',
          transitions: [
            {
              when: { contains: ['1', 'pronto', 'listo', 'ya'] },
              next_step: 'confirmar_llamada',
            },
            {
              when: { contains: ['2', 'meses', 'evaluando'] },
              next_step: 'confirmar_llamada',
            },
            {
              when: { contains: ['3', 'explorando', 'investigando'] },
              next_step: 'confirmar_llamada',
            },
            { when: { default: true }, next_step: 'confirmar_llamada' },
          ],
        },
        solicitud_horario: {
          message:
            '¿Qué día y horario te viene mejor? 📅\n\nEstamos disponibles {{horario}}.\n\nEscríbenos tu preferencia (ej: "Martes en la tarde" o "Viernes a las 11am").',
          transitions: [{ when: { default: true }, next_step: 'confirmado' }],
        },
        confirmado: {
          message:
            '¡Perfecto! 🎉 Hemos registrado tu preferencia.\n\nUn asesor de *{{desarrollo}}* te confirmará los detalles a la brevedad.\n\n📞 También puedes contactarnos: {{telefono}} · {{horario}}',
          action: 'open_conversation',
        },
        confirmar_llamada: {
          message:
            '¡Listo! 📞 Un asesor de *{{desarrollo}}* te llamará pronto al número con el que escribes.\n\nSi necesitas contactarnos antes:\n📞 {{telefono}} · {{horario}}',
          action: 'open_conversation',
        },
        no_entendido: {
          message:
            'No pude entender tu respuesta 😅\n\n¿Cómo prefieres dar el siguiente paso?\n\n1️⃣ Visitar el desarrollo\n2️⃣ Llamada con asesor\n3️⃣ Videollamada',
          transitions: [
            {
              when: { contains: ['1', 'visita', 'visitar'] },
              next_step: 'timeline',
            },
            {
              when: { contains: ['2', 'llamada', 'llamen'] },
              next_step: 'timeline_llamada',
            },
            {
              when: { contains: ['3', 'video', 'zoom'] },
              next_step: 'timeline',
            },
            { when: { default: true }, next_step: 'confirmar_llamada' },
          ],
        },
      },
      reactivation: {
        enabled: true,
        message:
          '👋 Hola, notamos que quedamos pendientes.\n\n¿Sigues interesado en conocer *{{desarrollo}}*? Solo responde a este mensaje y con gusto te atendemos.\n\n📞 También puedes llamarnos directo: {{telefono}}',
      },
    },
  },
  {
    id: 'atencion_general',
    name: 'Atención general — Calificación y handover',
    description:
      'Flujo básico para cualquier negocio. Saluda, pregunta el motivo y transfiere al área correcta.',
    icon: 'i-lucide-message-circle',
    config: {
      variables: {
        empresa: 'Mi Empresa',
        telefono: '55 1234 5678',
        horario: 'Lun–Vie 9am–6pm',
      },
      initial_step: 'bienvenida',
      steps: {
        bienvenida: {
          message:
            '¡Hola! 👋 Bienvenido a *{{empresa}}*.\n\n¿En qué podemos ayudarte hoy?\n\n1️⃣ Información o cotización\n2️⃣ Soporte o problema\n3️⃣ Hablar con alguien del equipo',
          transitions: [
            {
              when: {
                contains: [
                  '1',
                  'informacion',
                  'información',
                  'cotiz',
                  'precio',
                  'costo',
                ],
              },
              next_step: 'info',
            },
            {
              when: {
                contains: [
                  '2',
                  'soporte',
                  'problema',
                  'ayuda',
                  'falla',
                  'error',
                ],
              },
              next_step: 'soporte',
            },
            {
              when: {
                contains: ['3', 'hablar', 'asesor', 'persona', 'equipo'],
              },
              next_step: 'handover',
            },
            { when: { default: true }, next_step: 'no_entendido' },
          ],
        },
        info: {
          message:
            '¡Con gusto te ayudamos! 📋\n\nUn asesor de *{{empresa}}* revisará tu solicitud y te contactará pronto con toda la información.\n\n📞 Si necesitas atención inmediata: {{telefono}} · {{horario}}',
          action: 'open_conversation',
        },
        soporte: {
          message:
            'Entendido, te conectamos con nuestro equipo de soporte 🛠️\n\nUn especialista de *{{empresa}}* te atenderá en breve.\n\n📞 Línea directa: {{telefono}} · {{horario}}',
          action: 'open_conversation',
        },
        handover: {
          message:
            '¡Claro! Te conecto con alguien del equipo de *{{empresa}}* ahora mismo 👤\n\n📞 Si prefieres llamar: {{telefono}} · {{horario}}',
          action: 'open_conversation',
        },
        no_entendido: {
          message:
            'No pude entender tu respuesta 😅\n\n¿En qué podemos ayudarte?\n\n1️⃣ Información o cotización\n2️⃣ Soporte o problema\n3️⃣ Hablar con el equipo',
          transitions: [
            {
              when: { contains: ['1', 'informacion', 'información', 'cotiz'] },
              next_step: 'info',
            },
            {
              when: { contains: ['2', 'soporte', 'problema'] },
              next_step: 'soporte',
            },
            {
              when: { contains: ['3', 'hablar', 'asesor'] },
              next_step: 'handover',
            },
            { when: { default: true }, next_step: 'handover' },
          ],
        },
      },
      reactivation: {
        enabled: false,
        message: '',
      },
    },
  },
];
